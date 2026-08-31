begin;

create temporary table _sse_edge_response on commit drop as
select
    (response).status as http_status,
    (response).content as raw_content,
    case when ltrim((response).content) like '{%'
         then (response).content::jsonb else null end as payload
from (
    select extensions.http_post(
        'https://eqrqvyprikmwnlptzkao.supabase.co/functions/v1/capture-moutai-2021-sse-market',
        '{}',
        'application/json'
    ) as response
) request;

create temporary table _sse_edge_batch on commit drop as
with inserted as (
    insert into raw.ingestion_batches
        (source_id,status,adapter_version,request_params)
    select
        source_id,'running','capture-moutai-2021-sse-market-v1',
        jsonb_build_object(
            'function','capture-moutai-2021-sse-market',
            'security_code','600519.SH',
            'dates',jsonb_build_array('2021-03-31','2021-04-01'),
            'source_authority','official_exchange'
        )
    from raw.data_sources
    where source_code='SSE'
    returning batch_id,source_id
)
select * from inserted;

create temporary table _sse_edge_document on commit drop as
with eligible as (
    select
        r.payload,b.batch_id,b.source_id,s.security_id
    from _sse_edge_response r
    cross join _sse_edge_batch b
    cross join master.securities s
    where s.security_code='600519.SH'
      and r.http_status=200
      and r.payload->>'error' is null
      and length(coalesce(r.payload->>'raw_sha256',''))=64
      and length(coalesce(r.payload->>'bars_sha256',''))=64
      and jsonb_typeof(r.payload->'bars')='array'
      and jsonb_array_length(r.payload->'bars')>=2
), inserted as (
    insert into raw.documents
        (source_id,batch_id,security_id,document_type,title,source_url,
         storage_uri,mime_type,language,retrieved_at,content_hash,
         parser_version,metadata)
    select
        e.source_id,e.batch_id,e.security_id,
        'official_market_data_response_v2',
        'SSE 600519 official daily market response 2021-03-31 to 2021-04-01',
        e.payload->>'source_url',e.payload->>'raw_storage_uri',
        'application/json','zh-CN',
        coalesce(nullif(e.payload->>'captured_at','')::timestamptz,now()),
        e.payload->>'raw_sha256',e.payload->>'capture_version',
        e.payload||jsonb_build_object(
            'source_authority','official_exchange',
            'evidence_status','official_response_hashed'
        )
    from eligible e
    where not exists (
        select 1 from raw.documents d
        where d.source_id=e.source_id
          and d.security_id=e.security_id
          and d.document_type='official_market_data_response_v2'
          and d.content_hash=e.payload->>'raw_sha256'
    )
    returning document_id,batch_id,source_id,security_id,source_url,
              storage_uri,retrieved_at,content_hash,parser_version,metadata
), existing as (
    select d.document_id,d.batch_id,d.source_id,d.security_id,d.source_url,
           d.storage_uri,d.retrieved_at,d.content_hash,d.parser_version,d.metadata
    from raw.documents d
    join eligible e
      on d.source_id=e.source_id
     and d.security_id=e.security_id
     and d.document_type='official_market_data_response_v2'
     and d.content_hash=e.payload->>'raw_sha256'
)
select * from inserted
union all
select * from existing
limit 1;

create temporary table _sse_edge_bars on commit drop as
select
    d.document_id,d.batch_id,d.source_id,d.security_id,d.content_hash,
    bar,
    bar->>'trade_date' as trade_date_text,
    (bar->>'trade_date')::date as trade_date,
    nullif(bar->>'open_price','')::numeric as open_price,
    nullif(bar->>'high_price','')::numeric as high_price,
    nullif(bar->>'low_price','')::numeric as low_price,
    nullif(bar->>'close_price','')::numeric as close_price,
    nullif(bar->>'volume','')::numeric as volume,
    nullif(bar->>'turnover','')::numeric as turnover,
    encode(extensions.digest(convert_to(bar::text,'UTF8'),'sha256'),'hex')
        as record_hash
from _sse_edge_document d
cross join _sse_edge_response r
cross join lateral jsonb_array_elements(r.payload->'bars') rows(bar)
where bar->>'trade_date' in ('2021-03-31','2021-04-01')
  and nullif(bar->>'open_price','') is not null
  and nullif(bar->>'close_price','') is not null;

insert into raw.records
    (document_id,security_id,dataset_code,source_record_key,payload,
     published_at,available_at,record_hash,metadata)
select
    b.document_id,b.security_id,'sse_daily_market_v2',
    '600519|'||b.trade_date_text,b.bar,null,
    ((b.trade_date+time '15:15') at time zone 'Asia/Shanghai'),
    b.record_hash,
    jsonb_build_object(
        'source_authority','official_exchange',
        'raw_response_hash',b.content_hash,
        'field_map',b.bar->'field_map',
        'availability_policy','XSHG close plus 15-minute safety lag'
    )
from _sse_edge_bars b
on conflict (document_id,source_record_key) do update
set payload=excluded.payload,
    available_at=excluded.available_at,
    record_hash=excluded.record_hash,
    metadata=excluded.metadata;

insert into pit.market_bars
    (security_id,trade_date,open_price,high_price,low_price,close_price,
     volume,turnover,trading_status,currency,available_at,ingested_at,
     source_id,batch_id,record_hash,metadata)
select
    b.security_id,b.trade_date,b.open_price,b.high_price,b.low_price,
    b.close_price,b.volume,b.turnover,'trading','CNY',
    ((b.trade_date+time '15:15') at time zone 'Asia/Shanghai'),now(),
    b.source_id,b.batch_id,b.record_hash,
    jsonb_build_object(
        'source_document_id',b.document_id,
        'source_authority','official_exchange',
        'raw_response_hash',b.content_hash,
        'field_map',b.bar->'field_map',
        'availability_policy','XSHG close plus 15-minute safety lag',
        'evidence_grade',3,
        'capture_version','capture-moutai-2021-sse-market-v1'
    )
from _sse_edge_bars b
on conflict (security_id,trade_date,source_id,available_at) do update
set open_price=excluded.open_price,
    high_price=excluded.high_price,
    low_price=excluded.low_price,
    close_price=excluded.close_price,
    volume=excluded.volume,
    turnover=excluded.turnover,
    ingested_at=excluded.ingested_at,
    batch_id=excluded.batch_id,
    record_hash=excluded.record_hash,
    metadata=excluded.metadata;

create temporary table _sse_edge_comparison on commit drop as
select
    official.trade_date,
    official.open_price as official_open,
    derived.open_price as derived_open,
    official.close_price as official_close,
    derived.close_price as derived_close,
    official.record_hash as official_hash,
    derived.record_hash as derived_hash,
    official.metadata->>'source_document_id' as official_document_id,
    abs(official.open_price-derived.open_price)<=0.01
      and abs(official.close_price-derived.close_price)<=0.01 as matched
from pit.market_bars official
join raw.data_sources official_source
  on official_source.source_id=official.source_id
 and official_source.source_code='SSE'
join pit.market_bars derived
  on derived.security_id=official.security_id
 and derived.trade_date=official.trade_date
join raw.data_sources derived_source
  on derived_source.source_id=derived.source_id
 and derived_source.source_code='AKSHARE_EASTMONEY_DERIVED'
join master.securities security
  on security.security_id=official.security_id
 and security.security_code='600519.SH'
where official.trade_date in ('2021-03-31'::date,'2021-04-01'::date)
  and official.metadata->>'capture_version'='capture-moutai-2021-sse-market-v1';

update model.run_assumptions a
set provenance=a.provenance||jsonb_build_object(
        'official_source_code','SSE',
        'official_trade_date',c.trade_date,
        'official_document_id',c.official_document_id,
        'official_record_hash',c.official_hash,
        'derived_record_hash',c.derived_hash,
        'official_cross_validated',true,
        'cross_validation_tolerance',0.01,
        'cross_validation_version','sse-edge-reconciliation-v1'
    )
from _sse_edge_comparison c
where a.run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
  and a.scenario='control'
  and c.matched
  and (
      (a.assumption_key='reference_close_price'
       and c.trade_date='2021-03-31'::date
       and abs(a.value_numeric-c.official_close)<=0.01)
      or
      (a.assumption_key='execution_open_price'
       and c.trade_date='2021-04-01'::date
       and abs(a.value_numeric-c.official_open)<=0.01)
  );

update audit.evidence_assertions old
set status='superseded'
where old.subject_type='valuation_run_input'
  and old.subject_id in (
      '8bcbb9d3-7fdb-529a-9f9a-547043040e13|reference_close_price',
      '8bcbb9d3-7fdb-529a-9f9a-547043040e13|execution_open_price'
  )
  and old.status='active'
  and old.evidence_grade<3
  and (select count(*) from _sse_edge_comparison)=2
  and (select count(*) from _sse_edge_comparison where matched)=2;

insert into audit.evidence_assertions
    (assertion_code,subject_type,subject_id,as_of_at,evidence_grade,status,
     source_codes,content_hashes,unresolved_conflict,details,asserted_by)
select
    v.assertion_code,'valuation_run_input',
    '8bcbb9d3-7fdb-529a-9f9a-547043040e13|'||v.assertion_code,
    '2021-03-31T16:00:00Z'::timestamptz,3,'active',
    array['SSE','AKSHARE_EASTMONEY_DERIVED'],
    array_remove(array[d.content_hash,c.official_hash,c.derived_hash],null),
    false,
    jsonb_build_object(
        'official_trade_date',v.trade_date,
        'official_open',c.official_open,
        'derived_open',c.derived_open,
        'official_close',c.official_close,
        'derived_close',c.derived_close,
        'official_document_id',c.official_document_id,
        'validation','official SSE and independent derived source matched within 0.01',
        'capture_version','capture-moutai-2021-sse-market-v1'
    ),
    'sse-edge-reconciliation-v1'
from (values
    ('reference_close_price'::text,'2021-03-31'::date),
    ('execution_open_price'::text,'2021-04-01'::date)
) v(assertion_code,trade_date)
join _sse_edge_comparison c on c.trade_date=v.trade_date and c.matched
left join raw.documents d on d.document_id=(c.official_document_id)::uuid
where (select count(*) from _sse_edge_comparison)=2
  and (select count(*) from _sse_edge_comparison where matched)=2
  and not exists (
      select 1 from audit.evidence_assertions e
      where e.assertion_code=v.assertion_code
        and e.subject_type='valuation_run_input'
        and e.subject_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13|'||v.assertion_code
        and e.evidence_grade=3
        and e.status='active'
  );

with validation as (
    select
        count(*)::integer as compared_rows,
        count(*) filter(where matched)::integer as matched_rows,
        coalesce(jsonb_agg(
            jsonb_build_object(
                'trade_date',trade_date,
                'official_open',official_open,
                'derived_open',derived_open,
                'official_close',official_close,
                'derived_close',derived_close,
                'matched',matched
            ) order by trade_date
        ),'[]'::jsonb) as comparisons
    from _sse_edge_comparison
)
update audit.data_quality_issues q
set status=case when v.compared_rows=2 and v.matched_rows=2
                then 'resolved' else 'open' end,
    resolved_at=case when v.compared_rows=2 and v.matched_rows=2
                     then now() else null end,
    detected_at=now(),
    severity=case when v.compared_rows=2 and v.matched_rows=2
                  then 'info' else 'critical' end,
    description=case when v.compared_rows=2 and v.matched_rows=2
        then 'Decision and execution prices reconcile between official SSE data and the independent derived provider.'
        else 'Decision and execution prices do not yet have two matching official/derived observations.' end,
    details=jsonb_build_object(
        'compared_rows',v.compared_rows,
        'matched_rows',v.matched_rows,
        'comparisons',v.comparisons,
        'capture_version','capture-moutai-2021-sse-market-v1'
    )
from validation v
where q.rule_code='MARKET_PRICE_SECOND_SOURCE_REQUIRED'
  and q.record_key='600519.SH|2021-03-31|2021-04-01';

update audit.data_quality_issues q
set status='resolved',resolved_at=now(),
    details=q.details||jsonb_build_object(
        'resolved_by','capture-moutai-2021-sse-market-v1'
    )
where q.rule_code='SSE_MARKET_REFERENCE_PARSE_REQUIRED'
  and q.record_key='600519.SH|SSE_PARSE'
  and q.status='open'
  and (select count(*) from _sse_edge_comparison)=2
  and (select count(*) from _sse_edge_comparison where matched)=2;

insert into audit.data_quality_issues
    (severity,domain,table_name,record_key,rule_code,description,status,details)
select
    'critical','market_data','raw.documents',
    '600519.SH|2021-03-31|2021-04-01',
    'OFFICIAL_SSE_MARKET_CAPTURE_FAILED',
    'The fixed server-side SSE market capture did not produce two official daily bars.',
    'open',
    jsonb_build_object(
        'http_status',r.http_status,
        'response',coalesce(r.payload,to_jsonb(r.raw_content)),
        'function','capture-moutai-2021-sse-market'
    )
from _sse_edge_response r
where (select count(*) from _sse_edge_bars)<>2
  and not exists (
      select 1 from audit.data_quality_issues q
      where q.rule_code='OFFICIAL_SSE_MARKET_CAPTURE_FAILED'
        and q.record_key='600519.SH|2021-03-31|2021-04-01'
        and q.status='open'
  );

update audit.data_quality_issues q
set status='resolved',resolved_at=now(),
    details=q.details||jsonb_build_object(
        'resolved_by','subsequent successful SSE Edge capture'
    )
where q.rule_code='OFFICIAL_SSE_MARKET_CAPTURE_FAILED'
  and q.record_key='600519.SH|2021-03-31|2021-04-01'
  and q.status='open'
  and (select count(*) from _sse_edge_bars)=2;

insert into audit.data_quality_issues
    (severity,domain,table_name,record_key,rule_code,description,status,details)
select
    'critical','market_data','pit.market_bars',
    '600519.SH|2021-03-31|2021-04-01',
    'SSE_MARKET_REFERENCE_MISMATCH',
    'Official SSE bars and independent derived bars disagree beyond the 0.01 tolerance.',
    'open',
    jsonb_build_object(
        'compared_rows',v.compared_rows,
        'matched_rows',v.matched_rows,
        'comparisons',v.comparisons
    )
from (
    select
        count(*)::integer as compared_rows,
        count(*) filter(where matched)::integer as matched_rows,
        coalesce(jsonb_agg(
            jsonb_build_object(
                'trade_date',trade_date,
                'official_open',official_open,
                'derived_open',derived_open,
                'official_close',official_close,
                'derived_close',derived_close,
                'matched',matched
            ) order by trade_date
        ),'[]'::jsonb) as comparisons
    from _sse_edge_comparison
) v
where v.compared_rows=2
  and v.matched_rows<2
  and not exists (
      select 1 from audit.data_quality_issues q
      where q.rule_code='SSE_MARKET_REFERENCE_MISMATCH'
        and q.record_key='600519.SH|2021-03-31|2021-04-01'
        and q.status='open'
  );

update audit.data_quality_issues q
set status='resolved',resolved_at=now(),
    details=q.details||jsonb_build_object(
        'resolved_by','subsequent matching SSE Edge capture'
    )
where q.rule_code='SSE_MARKET_REFERENCE_MISMATCH'
  and q.record_key='600519.SH|2021-03-31|2021-04-01'
  and q.status='open'
  and (select count(*) from _sse_edge_comparison)=2
  and (select count(*) from _sse_edge_comparison where matched)=2;

update raw.ingestion_batches b
set status=case when exists(
        select 1 from _sse_edge_bars
    ) then 'completed' else 'failed' end,
    completed_at=now(),
    row_count=(select count(*) from _sse_edge_bars),
    batch_hash=(select content_hash from _sse_edge_document limit 1),
    error_text=case when exists(select 1 from _sse_edge_bars) then null
                    else left(coalesce(
                        (select payload->>'error' from _sse_edge_response),
                        (select raw_content from _sse_edge_response),
                        'SSE Edge capture returned no official bars'
                    ),2000) end
where b.batch_id in(select batch_id from _sse_edge_batch);

commit;
