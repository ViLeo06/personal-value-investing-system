begin;

create temporary table _sse_response on commit drop as
select
    'https://query.sse.com.cn/commonQuery.do?isPagination=true&sqlId=COMMON_SSE_SJ_GPSJ_CJGK_MRGK_C&productId=600519&beginDate=20210331&endDate=20210401&pageHelp.pageSize=100&pageHelp.pageNo=1&pageHelp.beginPage=1&pageHelp.cacheSize=1'::text as source_url,
    (response).status as http_status,
    (response).content as raw_content,
    case
        when ltrim((response).content) like '{%'
            then (response).content::jsonb
        else null
    end as payload
from (
    select extensions.http_get(
        'https://query.sse.com.cn/commonQuery.do?isPagination=true&sqlId=COMMON_SSE_SJ_GPSJ_CJGK_MRGK_C&productId=600519&beginDate=20210331&endDate=20210401&pageHelp.pageSize=100&pageHelp.pageNo=1&pageHelp.beginPage=1&pageHelp.cacheSize=1'
    ) as response
) request;

create temporary table _sse_batch on commit drop as
with inserted as (
    insert into raw.ingestion_batches
        (source_id,status,adapter_version,request_params)
    select
        source_id,'running','sse-market-history-v2',
        jsonb_build_object(
            'productId','600519',
            'beginDate','20210331',
            'endDate','20210401',
            'sqlId','COMMON_SSE_SJ_GPSJ_CJGK_MRGK_C'
        )
    from raw.data_sources
    where source_code='SSE'
    returning batch_id,source_id
)
select * from inserted;

create temporary table _sse_document on commit drop as
with inserted as (
    insert into raw.documents
        (source_id,batch_id,security_id,document_type,title,source_url,mime_type,
         language,retrieved_at,content_hash,parser_version,metadata)
    select
        b.source_id,b.batch_id,s.security_id,
        'official_market_data_response',
        'SSE 600519 daily market reference 2021-03-31 to 2021-04-01',
        r.source_url,'application/json','zh-CN',now(),
        encode(extensions.digest(convert_to(r.raw_content,'UTF8'),'sha256'),'hex'),
        'sse-market-history-v2',
        jsonb_build_object(
            'http_status',r.http_status,
            'raw_response',r.raw_content,
            'payload',r.payload,
            'source_authority','official_exchange'
        )
    from _sse_response r
    cross join _sse_batch b
    cross join master.securities s
    where s.security_code='600519.SH'
      and r.http_status=200
    returning document_id,batch_id,source_id,security_id,content_hash
)
select * from inserted;

create temporary table _sse_rows on commit drop as
select
    d.document_id,d.batch_id,d.source_id,d.security_id,d.content_hash,
    row_payload,
    row_number() over(order by row_payload::text) as row_no
from _sse_document d
cross join _sse_response r
cross join lateral jsonb_array_elements(
    coalesce(
        r.payload->'result',
        r.payload->'data',
        r.payload->'pageHelp'->'data',
        '[]'::jsonb
    )
) rows(row_payload);

insert into raw.records
    (document_id,security_id,dataset_code,source_record_key,payload,
     published_at,available_at,record_hash,metadata)
select
    r.document_id,r.security_id,'sse_daily_market',
    concat_ws('|','600519',coalesce(
        r.row_payload->>'TRADEDATE',
        r.row_payload->>'TRADE_DATE',
        r.row_payload->>'DATE',
        r.row_no::text
    )),
    r.row_payload,null,null,
    encode(extensions.digest(convert_to(r.row_payload::text,'UTF8'),'sha256'),'hex'),
    jsonb_build_object(
        'source_authority','official_exchange',
        'field_count',jsonb_object_length(r.row_payload)
    )
from _sse_rows r
on conflict (document_id,source_record_key) do nothing;

create temporary table _sse_parsed on commit drop as
select
    r.document_id,r.batch_id,r.source_id,r.security_id,r.content_hash,
    encode(extensions.digest(convert_to(r.row_payload::text,'UTF8'),'sha256'),'hex') as record_hash,
    case
        when coalesce(
            r.row_payload->>'TRADEDATE',
            r.row_payload->>'TRADE_DATE',
            r.row_payload->>'DATE'
        ) ~ '^\d{4}-?\d{2}-?\d{2}'
        then to_date(
            replace(left(coalesce(
                r.row_payload->>'TRADEDATE',
                r.row_payload->>'TRADE_DATE',
                r.row_payload->>'DATE'
            ),10),'-',''),
            'YYYYMMDD'
        )
    end as trade_date,
    nullif(coalesce(r.row_payload->>'OPENPRICE',r.row_payload->>'OPEN_PRICE',r.row_payload->>'OPEN'),'')::numeric as open_price,
    nullif(coalesce(r.row_payload->>'HIGHESTPRICE',r.row_payload->>'HIGH_PRICE',r.row_payload->>'HIGH'),'')::numeric as high_price,
    nullif(coalesce(r.row_payload->>'LOWESTPRICE',r.row_payload->>'LOW_PRICE',r.row_payload->>'LOW'),'')::numeric as low_price,
    nullif(coalesce(r.row_payload->>'CLOSEPRICE',r.row_payload->>'CLOSE_PRICE',r.row_payload->>'CLOSE'),'')::numeric as close_price,
    nullif(coalesce(r.row_payload->>'TOTALVOLUME',r.row_payload->>'VOLUME'),'')::numeric as volume,
    nullif(coalesce(r.row_payload->>'TOTALAMOUNT',r.row_payload->>'AMOUNT',r.row_payload->>'TURNOVER'),'')::numeric as turnover
from _sse_rows r;

insert into pit.market_bars
    (security_id,trade_date,open_price,high_price,low_price,close_price,
     volume,turnover,trading_status,currency,available_at,ingested_at,
     source_id,batch_id,record_hash,metadata)
select
    p.security_id,p.trade_date,p.open_price,p.high_price,p.low_price,p.close_price,
    p.volume,p.turnover,'trading','CNY',
    ((p.trade_date+time '15:15') at time zone 'Asia/Shanghai'),now(),
    p.source_id,p.batch_id,p.record_hash,
    jsonb_build_object(
        'source_document_id',p.document_id,
        'source_authority','official_exchange',
        'availability_policy','XSHG close plus 15-minute safety lag',
        'evidence_grade',3
    )
from _sse_parsed p
where p.trade_date in ('2021-03-31'::date,'2021-04-01'::date)
  and p.open_price is not null
  and p.close_price is not null
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

create temporary table _sse_comparison on commit drop as
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
where official.trade_date in ('2021-03-31'::date,'2021-04-01'::date);

update audit.data_quality_issues q
set status=case when v.compared_rows=2 and v.matched_rows=2 then 'resolved' else q.status end,
    resolved_at=case when v.compared_rows=2 and v.matched_rows=2 then now() else q.resolved_at end,
    details=q.details||jsonb_build_object(
        'sse_comparison',v.comparisons,
        'compared_rows',v.compared_rows,
        'matched_rows',v.matched_rows
    )
from (
    select
        count(*) as compared_rows,
        count(*) filter(where matched) as matched_rows,
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
    from _sse_comparison
) v
where q.rule_code='MARKET_PRICE_SECOND_SOURCE_REQUIRED'
  and q.record_key='600519.SH|2021-03-31|2021-04-01'
  and q.status='open';

update audit.evidence_assertions old
set status='superseded'
where old.subject_type='valuation_run_input'
  and old.subject_id in (
      '8bcbb9d3-7fdb-529a-9f9a-547043040e13|reference_close_price',
      '8bcbb9d3-7fdb-529a-9f9a-547043040e13|execution_open_price'
  )
  and old.status='active'
  and (select count(*) from _sse_comparison)=2
  and (select count(*) from _sse_comparison where matched)=2;

insert into audit.evidence_assertions
    (assertion_code,subject_type,subject_id,as_of_at,evidence_grade,status,
     source_codes,content_hashes,unresolved_conflict,details,asserted_by)
select
    v.assertion_code,'valuation_run_input',
    '8bcbb9d3-7fdb-529a-9f9a-547043040e13|'||v.assertion_code,
    '2021-03-31T16:00:00Z'::timestamptz,
    3,'active',array['SSE','AKSHARE_EASTMONEY_DERIVED'],
    array_remove(array[d.content_hash,c.official_hash,c.derived_hash],null),
    false,
    jsonb_build_object(
        'official_trade_date',v.trade_date,
        'validation','official SSE and independent derived source matched within 0.01'
    ),
    'sse-eastmoney-market-reconciliation-v2'
from (values
    ('reference_close_price'::text,'2021-03-31'::date),
    ('execution_open_price'::text,'2021-04-01'::date)
) v(assertion_code,trade_date)
join _sse_comparison c on c.trade_date=v.trade_date and c.matched
left join raw.documents d on d.document_id=(c.official_document_id)::uuid
where (select count(*) from _sse_comparison)=2
  and (select count(*) from _sse_comparison where matched)=2
  and not exists (
      select 1 from audit.evidence_assertions e
      where e.assertion_code=v.assertion_code
        and e.subject_type='valuation_run_input'
        and e.subject_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13|'||v.assertion_code
        and e.evidence_grade=3
        and e.status='active'
  );

insert into audit.data_quality_issues
    (severity,domain,table_name,record_key,rule_code,description,status,details)
select
    'critical','market_data','pit.market_bars',
    '600519.SH|SSE_PARSE',
    'SSE_MARKET_REFERENCE_PARSE_REQUIRED',
    'SSE official response was archived but did not produce two matching parsed market rows.',
    'open',
    jsonb_build_object(
        'http_status',(select http_status from _sse_response),
        'parsed_rows',(select count(*) from _sse_parsed where trade_date is not null),
        'compared_rows',(select count(*) from _sse_comparison),
        'matched_rows',(select count(*) from _sse_comparison where matched),
        'candidate_fields',coalesce((
            select jsonb_agg(distinct key order by key)
            from _sse_rows r
            cross join lateral jsonb_object_keys(r.row_payload) key
            where key~*'(DATE|OPEN|CLOSE|HIGH|LOW|VOLUME|AMOUNT)'
        ),'[]'::jsonb)
    )
where not (
    (select count(*) from _sse_comparison)=2
    and (select count(*) from _sse_comparison where matched)=2
)
  and not exists (
      select 1 from audit.data_quality_issues q
      where q.rule_code='SSE_MARKET_REFERENCE_PARSE_REQUIRED'
        and q.record_key='600519.SH|SSE_PARSE'
        and q.status='open'
  );

update raw.ingestion_batches b
set status=case when exists(
        select 1 from pit.market_bars m
        join raw.data_sources s on s.source_id=m.source_id
        where s.source_code='SSE'
          and m.trade_date in ('2021-03-31'::date,'2021-04-01'::date)
    ) then 'completed' else 'failed' end,
    completed_at=now(),
    row_count=(
        select count(*) from pit.market_bars m
        join raw.data_sources s on s.source_id=m.source_id
        join master.securities sec on sec.security_id=m.security_id
        where s.source_code='SSE'
          and sec.security_code='600519.SH'
          and m.trade_date in ('2021-03-31'::date,'2021-04-01'::date)
    ),
    error_text=case when exists(
        select 1 from pit.market_bars m
        join raw.data_sources s on s.source_id=m.source_id
        where s.source_code='SSE'
          and m.trade_date in ('2021-03-31'::date,'2021-04-01'::date)
    ) then null else 'SSE response archived but no parsable official bars were produced' end
where b.batch_id in(select batch_id from _sse_batch);

commit;
