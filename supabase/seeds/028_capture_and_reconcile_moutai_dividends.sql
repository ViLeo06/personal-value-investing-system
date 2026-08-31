begin;

create temporary table _dividend_response on commit drop as
select
    (response).status as http_status,
    (response).content as raw_content,
    case when ltrim((response).content) like '{%'
         then (response).content::jsonb else null end as payload
from (
    select extensions.http_post(
        'https://eqrqvyprikmwnlptzkao.supabase.co/functions/v1/capture-moutai-dividend-announcements',
        '{}',
        'application/json'
    ) as response
) request;

create temporary table _dividend_batch on commit drop as
with inserted as (
    insert into raw.ingestion_batches
        (source_id,status,adapter_version,request_params)
    select
        source_id,'running','capture-moutai-dividend-announcements-v1',
        jsonb_build_object(
            'function','capture-moutai-dividend-announcements',
            'security_code','600519.SH',
            'period_start','2021-04-01',
            'period_end','2026-04-01',
            'source_authority','official_disclosure'
        )
    from raw.data_sources
    where source_code='CNINFO'
    returning batch_id,source_id
)
select * from inserted;

create temporary table _dividend_items on commit drop as
select
    b.batch_id,b.source_id,i.issuer_id,s.security_id,
    r.payload as manifest_payload,
    item,
    item->>'announcement_id' as announcement_id,
    item->>'announcement_title' as announcement_title,
    nullif(item->>'published_at','')::timestamptz as published_at,
    item->>'source_url' as source_url,
    item->>'storage_uri' as storage_uri,
    item->>'pdf_sha256' as pdf_sha256,
    item->>'text_sha256' as text_sha256,
    nullif(item->>'pdf_bytes','')::bigint as pdf_bytes,
    nullif(item->>'page_count','')::integer as page_count,
    item->'parsed_fields' as parsed_fields,
    coalesce((item->>'evidence_grade_candidate')::smallint,2) as evidence_grade_candidate
from _dividend_response r
cross join _dividend_batch b
cross join master.issuers i
cross join master.securities s
cross join lateral jsonb_array_elements(
    case when jsonb_typeof(r.payload->'documents')='array'
         then r.payload->'documents' else '[]'::jsonb end
) rows(item)
where i.issuer_code='KWEICHOW_MOUTAI'
  and s.security_code='600519.SH'
  and r.http_status=200
  and r.payload->>'error' is null
  and length(coalesce(item->>'announcement_id',''))>0
  and length(coalesce(item->>'pdf_sha256',''))=64;

create temporary table _dividend_manifest_document on commit drop as
with eligible as (
    select distinct
        b.batch_id,b.source_id,i.issuer_id,s.security_id,r.payload
    from _dividend_response r
    cross join _dividend_batch b
    cross join master.issuers i
    cross join master.securities s
    where i.issuer_code='KWEICHOW_MOUTAI'
      and s.security_code='600519.SH'
      and r.http_status=200
      and r.payload->>'error' is null
      and length(coalesce(r.payload->>'manifest_sha256',''))=64
), inserted as (
    insert into raw.documents
        (source_id,batch_id,issuer_id,security_id,document_type,title,
         source_url,storage_uri,mime_type,language,retrieved_at,
         content_hash,parser_version,metadata)
    select
        e.source_id,e.batch_id,e.issuer_id,e.security_id,
        'official_dividend_manifest',
        '贵州茅台2021-2026权益分派实施公告清单',
        'https://www.cninfo.com.cn/new/hisAnnouncement/query',
        'supabase://official-evidence/gate0/moutai/corporate-actions/2021-04-01_2026-04-01/manifest_v1.json',
        'application/json','zh-CN',
        coalesce(nullif(e.payload->>'captured_at','')::timestamptz,now()),
        e.payload->>'manifest_sha256',e.payload->>'capture_version',
        e.payload||jsonb_build_object(
            'source_authority','official_disclosure',
            'formal_event_promotion_allowed',false
        )
    from eligible e
    where not exists (
        select 1 from raw.documents d
        where d.source_id=e.source_id
          and d.issuer_id=e.issuer_id
          and d.document_type='official_dividend_manifest'
          and d.content_hash=e.payload->>'manifest_sha256'
    )
    returning *
), existing as (
    select d.*
    from raw.documents d
    join eligible e
      on d.source_id=e.source_id
     and d.issuer_id=e.issuer_id
     and d.document_type='official_dividend_manifest'
     and d.content_hash=e.payload->>'manifest_sha256'
)
select * from inserted
union all
select * from existing
limit 1;

create temporary table _dividend_documents on commit drop as
with inserted as (
    insert into raw.documents
        (source_id,batch_id,issuer_id,security_id,document_type,title,
         source_url,storage_uri,mime_type,language,published_at,
         retrieved_at,content_hash,parser_version,metadata)
    select
        x.source_id,x.batch_id,x.issuer_id,x.security_id,
        'official_dividend_implementation_pdf',
        x.announcement_title,x.source_url,x.storage_uri,
        'application/pdf','zh-CN',x.published_at,
        coalesce(nullif(x.manifest_payload->>'captured_at','')::timestamptz,now()),
        x.pdf_sha256,x.item->>'parser',
        x.item||jsonb_build_object(
            'announcement_id',x.announcement_id,
            'catalog_sha256',x.manifest_payload->>'catalog_sha256',
            'manifest_sha256',x.manifest_payload->>'manifest_sha256',
            'source_authority','official_disclosure',
            'event_fields_complete',coalesce((x.parsed_fields->>'complete')::boolean,false),
            'formal_event_promotion_allowed',false
        )
    from _dividend_items x
    where not exists (
        select 1 from raw.documents d
        where d.source_id=x.source_id
          and d.security_id=x.security_id
          and d.document_type='official_dividend_implementation_pdf'
          and d.content_hash=x.pdf_sha256
    )
    returning document_id,batch_id,source_id,issuer_id,security_id,title,
              source_url,storage_uri,published_at,retrieved_at,content_hash,
              parser_version,metadata
), existing as (
    select d.document_id,d.batch_id,d.source_id,d.issuer_id,d.security_id,d.title,
           d.source_url,d.storage_uri,d.published_at,d.retrieved_at,d.content_hash,
           d.parser_version,d.metadata
    from raw.documents d
    join _dividend_items x
      on d.source_id=x.source_id
     and d.security_id=x.security_id
     and d.document_type='official_dividend_implementation_pdf'
     and d.content_hash=x.pdf_sha256
)
select * from inserted
union all
select * from existing;

insert into raw.records
    (document_id,issuer_id,security_id,dataset_code,source_record_key,payload,
     published_at,available_at,record_hash,metadata)
select
    d.document_id,d.issuer_id,d.security_id,
    'cninfo_dividend_implementation_event_v1',
    d.metadata->>'announcement_id',
    x.item,d.published_at,d.published_at,
    encode(extensions.digest(convert_to(x.item::text,'UTF8'),'sha256'),'hex'),
    jsonb_build_object(
        'source_authority','official_disclosure',
        'official_pdf_hash',d.content_hash,
        'text_sha256',x.text_sha256,
        'catalog_sha256',x.manifest_payload->>'catalog_sha256',
        'manifest_sha256',x.manifest_payload->>'manifest_sha256',
        'parsed_fields_complete',coalesce((x.parsed_fields->>'complete')::boolean,false),
        'candidate_evidence_grade',x.evidence_grade_candidate,
        'formal_event_promotion_allowed',false
    )
from _dividend_documents d
join _dividend_items x
  on x.announcement_id=d.metadata->>'announcement_id'
on conflict (document_id,source_record_key) do update
set payload=excluded.payload,
    published_at=excluded.published_at,
    available_at=excluded.available_at,
    record_hash=excluded.record_hash,
    metadata=excluded.metadata;

create temporary table _dividend_records on commit drop as
select
    r.record_id,r.document_id,r.issuer_id,r.security_id,r.payload,
    r.published_at,r.record_hash,r.metadata,
    r.payload->>'announcement_id' as announcement_id,
    r.payload->>'announcement_title' as announcement_title,
    nullif(r.payload->'parsed_fields'->>'ex_date','')::date as official_ex_date,
    nullif(r.payload->'parsed_fields'->>'record_date','')::date as official_record_date,
    nullif(r.payload->'parsed_fields'->>'payment_date','')::date as official_payment_date,
    nullif(r.payload->'parsed_fields'->>'cash_amount_per_share','')::numeric
        as official_cash_amount_per_share,
    coalesce(r.payload->'parsed_fields'->>'currency','CNY') as official_currency,
    coalesce((r.payload->'parsed_fields'->>'complete')::boolean,false) as complete
from raw.records r
join _dividend_documents d on d.document_id=r.document_id
where r.dataset_code='cninfo_dividend_implementation_event_v1';

create temporary table _dividend_match_candidates on commit drop as
with candidates as (
    select
        o.*,
        ca.action_id,
        ca.ex_date as observed_ex_date,
        ca.record_date as observed_record_date,
        ca.payment_date as observed_payment_date,
        ca.cash_amount_per_share as observed_cash_amount_per_share,
        ca.currency as observed_currency,
        ca.record_hash as observed_record_hash,
        ca.source_document_id as observed_source_document_id,
        abs(ca.ex_date-o.official_ex_date)::integer as date_difference_days,
        abs(ca.cash_amount_per_share-o.official_cash_amount_per_share)
            as amount_difference,
        row_number() over(
            partition by o.record_id
            order by
                case when ca.ex_date=o.official_ex_date then 0 else 1 end,
                abs(ca.ex_date-o.official_ex_date),
                abs(ca.cash_amount_per_share-o.official_cash_amount_per_share),
                ca.action_id
        ) as rn
    from _dividend_records o
    join pit.corporate_actions ca
      on ca.security_id=o.security_id
     and ca.action_type='cash_dividend'
     and ca.ex_date between o.official_ex_date-interval '10 days'
                        and o.official_ex_date+interval '10 days'
     and abs(ca.cash_amount_per_share-o.official_cash_amount_per_share)<=0.000001
    where o.complete
      and o.official_ex_date between '2021-04-01'::date and '2026-04-01'::date
      and o.official_cash_amount_per_share>0
)
select * from candidates where rn=1;

insert into audit.corporate_action_matches
    (action_id,official_document_id,official_record_id,announcement_id,
     announcement_title,official_published_at,official_ex_date,
     official_record_date,official_payment_date,official_cash_amount_per_share,
     official_currency,observed_ex_date,observed_record_date,
     observed_payment_date,observed_cash_amount_per_share,observed_currency,
     date_difference_days,amount_difference,field_checks,status,metadata,
     validated_at)
select
    c.action_id,c.document_id,c.record_id,c.announcement_id,c.announcement_title,
    c.published_at,c.official_ex_date,c.official_record_date,
    c.official_payment_date,c.official_cash_amount_per_share,c.official_currency,
    c.observed_ex_date,c.observed_record_date,c.observed_payment_date,
    c.observed_cash_amount_per_share,c.observed_currency,
    c.date_difference_days,c.amount_difference,
    jsonb_build_object(
        'ex_date_exact',c.observed_ex_date=c.official_ex_date,
        'record_date_compatible',c.observed_record_date is null
            or c.observed_record_date=c.official_record_date,
        'payment_date_compatible',c.observed_payment_date is null
            or c.observed_payment_date=c.official_payment_date,
        'amount_exact',c.amount_difference<=0.000001,
        'currency_compatible',c.observed_currency is null
            or c.observed_currency=c.official_currency
    ),
    case when
        c.observed_ex_date=c.official_ex_date
        and c.amount_difference<=0.000001
        and (c.observed_record_date is null
             or c.observed_record_date=c.official_record_date)
        and (c.observed_payment_date is null
             or c.observed_payment_date=c.official_payment_date)
        and (c.observed_currency is null
             or c.observed_currency=c.official_currency)
        then 'validated' else 'conflict' end,
    jsonb_build_object(
        'official_pdf_hash',d.content_hash,
        'official_record_hash',c.record_hash,
        'observed_record_hash',c.observed_record_hash,
        'previous_source_document_id',c.observed_source_document_id,
        'parser',d.parser_version,
        'matching_version','corporate-action-official-match-v1'
    ),
    case when
        c.observed_ex_date=c.official_ex_date
        and c.amount_difference<=0.000001
        and (c.observed_record_date is null
             or c.observed_record_date=c.official_record_date)
        and (c.observed_payment_date is null
             or c.observed_payment_date=c.official_payment_date)
        and (c.observed_currency is null
             or c.observed_currency=c.official_currency)
        then now() else null end
from _dividend_match_candidates c
join raw.documents d on d.document_id=c.document_id
on conflict (action_id,official_document_id) do update
set official_record_id=excluded.official_record_id,
    announcement_id=excluded.announcement_id,
    announcement_title=excluded.announcement_title,
    official_published_at=excluded.official_published_at,
    official_ex_date=excluded.official_ex_date,
    official_record_date=excluded.official_record_date,
    official_payment_date=excluded.official_payment_date,
    official_cash_amount_per_share=excluded.official_cash_amount_per_share,
    official_currency=excluded.official_currency,
    observed_ex_date=excluded.observed_ex_date,
    observed_record_date=excluded.observed_record_date,
    observed_payment_date=excluded.observed_payment_date,
    observed_cash_amount_per_share=excluded.observed_cash_amount_per_share,
    observed_currency=excluded.observed_currency,
    date_difference_days=excluded.date_difference_days,
    amount_difference=excluded.amount_difference,
    field_checks=excluded.field_checks,
    status=excluded.status,
    metadata=excluded.metadata,
    validated_at=excluded.validated_at;

update pit.corporate_actions ca
set announced_at=m.official_published_at,
    available_at=m.official_published_at,
    ex_date=m.official_ex_date,
    record_date=m.official_record_date,
    payment_date=m.official_payment_date,
    effective_date=m.official_ex_date,
    cash_amount_per_share=m.official_cash_amount_per_share,
    currency=m.official_currency,
    source_document_id=m.official_document_id,
    record_hash=encode(
        extensions.digest(
            convert_to(concat_ws('|',
                ca.security_id::text,ca.action_type,m.official_published_at::text,
                m.official_ex_date::text,m.official_record_date::text,
                m.official_payment_date::text,
                m.official_cash_amount_per_share::text,m.official_currency,
                d.content_hash
            ),'UTF8'),
            'sha256'
        ),
        'hex'
    ),
    metadata=ca.metadata||jsonb_build_object(
        'official_match_id',m.match_id,
        'official_announcement_id',m.announcement_id,
        'official_announcement_title',m.announcement_title,
        'official_document_id',m.official_document_id,
        'official_pdf_hash',d.content_hash,
        'official_record_id',m.official_record_id,
        'official_record_hash',r.record_hash,
        'previous_source_document_id',m.metadata->>'previous_source_document_id',
        'source_authority','official_disclosure',
        'evidence_grade',3,
        'matching_version','corporate-action-official-match-v1'
    )
from audit.corporate_action_matches m
join raw.documents d on d.document_id=m.official_document_id
join raw.records r on r.record_id=m.official_record_id
where m.action_id=ca.action_id
  and m.status='validated';

update audit.evidence_assertions e
set status='superseded'
where e.assertion_code='cash_dividend'
  and e.subject_type='corporate_action'
  and e.status='active'
  and e.evidence_grade<3
  and exists (
      select 1
      from audit.corporate_action_matches m
      where m.action_id::text=e.subject_id
        and m.status='validated'
  );

insert into audit.evidence_assertions
    (assertion_code,subject_type,subject_id,as_of_at,evidence_grade,status,
     source_codes,content_hashes,unresolved_conflict,details,asserted_by)
select
    'cash_dividend','corporate_action',m.action_id::text,
    m.official_published_at,3,'active',
    array['CNINFO','AKSHARE_EASTMONEY_DERIVED'],
    array_remove(array[
        d.content_hash,
        r.record_hash,
        m.metadata->>'observed_record_hash'
    ],null),
    false,
    jsonb_build_object(
        'match_id',m.match_id,
        'announcement_id',m.announcement_id,
        'announcement_title',m.announcement_title,
        'official_document_id',m.official_document_id,
        'official_record_id',m.official_record_id,
        'ex_date',m.official_ex_date,
        'record_date',m.official_record_date,
        'payment_date',m.official_payment_date,
        'cash_amount_per_share',m.official_cash_amount_per_share,
        'currency',m.official_currency,
        'field_checks',m.field_checks,
        'quality_reason','derived corporate action reconciled exactly to a hashed official implementation announcement'
    ),
    'corporate-action-official-match-v1'
from audit.corporate_action_matches m
join raw.documents d on d.document_id=m.official_document_id
join raw.records r on r.record_id=m.official_record_id
where m.status='validated'
  and not exists (
      select 1 from audit.evidence_assertions e
      where e.assertion_code='cash_dividend'
        and e.subject_type='corporate_action'
        and e.subject_id=m.action_id::text
        and e.evidence_grade=3
        and e.status='active'
  );

create temporary table _dividend_reconciliation on commit drop as
with actions as (
    select ca.action_id
    from pit.corporate_actions ca
    join master.securities s on s.security_id=ca.security_id
    where s.security_code='600519.SH'
      and ca.action_type='cash_dividend'
      and ca.ex_date between '2021-04-01'::date and '2026-04-01'::date
), official as (
    select record_id
    from _dividend_records
    where complete
      and official_ex_date between '2021-04-01'::date and '2026-04-01'::date
      and official_cash_amount_per_share>0
), validated as (
    select distinct action_id,official_record_id
    from audit.corporate_action_matches
    where status='validated'
)
select
    (select count(*) from actions)::integer as action_count,
    (select count(*) from official)::integer as complete_official_count,
    (select count(distinct action_id) from validated)::integer
        as validated_action_count,
    (select count(distinct official_record_id) from validated)::integer
        as matched_official_count,
    coalesce((
        select jsonb_agg(a.action_id order by a.action_id)
        from actions a
        where not exists (
            select 1 from validated v where v.action_id=a.action_id
        )
    ),'[]'::jsonb) as unmatched_actions,
    coalesce((
        select jsonb_agg(o.record_id order by o.record_id)
        from official o
        where not exists (
            select 1 from validated v where v.official_record_id=o.record_id
        )
    ),'[]'::jsonb) as unmatched_official_records;

with s as (select * from _dividend_reconciliation)
update audit.data_quality_issues q
set severity=case when s.action_count>0
                        and s.action_count=s.validated_action_count
                        and s.complete_official_count=s.matched_official_count
                  then 'info' else 'critical' end,
    status=case when s.action_count>0
                      and s.action_count=s.validated_action_count
                      and s.complete_official_count=s.matched_official_count
                then 'resolved' else 'open' end,
    resolved_at=case when s.action_count>0
                           and s.action_count=s.validated_action_count
                           and s.complete_official_count=s.matched_official_count
                     then now() else null end,
    detected_at=now(),
    description=case when s.action_count>0
                           and s.action_count=s.validated_action_count
                           and s.complete_official_count=s.matched_official_count
        then 'Every Moutai cash dividend in the holding window reconciles to one official implementation announcement.'
        else 'One or more Moutai cash dividends or official implementation announcements remain unmatched.' end,
    details=jsonb_build_object(
        'action_count',s.action_count,
        'complete_official_count',s.complete_official_count,
        'validated_action_count',s.validated_action_count,
        'matched_official_count',s.matched_official_count,
        'unmatched_actions',s.unmatched_actions,
        'unmatched_official_records',s.unmatched_official_records,
        'matching_version','corporate-action-official-match-v1'
    )
from s
where q.rule_code in (
        'CORPORATE_ACTION_SECOND_SOURCE_REQUIRED',
        'CORPORATE_ACTION_FIELD_MAPPING_REVIEW_REQUIRED',
        'CORPORATE_ACTION_OFFICIAL_MATCH_REQUIRED'
    )
  and q.record_key in (
        '600519.SH|2021-2026|CASH_DIVIDENDS',
        '600519.SH|DIVIDEND_FIELDS',
        '600519.SH|2021-04-01|2026-04-01'
    );

with s as (select * from _dividend_reconciliation)
insert into audit.data_quality_issues
    (severity,domain,table_name,record_key,rule_code,description,status,details,
     resolved_at)
select
    case when s.action_count>0
                   and s.action_count=s.validated_action_count
                   and s.complete_official_count=s.matched_official_count
         then 'info' else 'critical' end,
    'corporate_action_evidence','audit.corporate_action_matches',
    '600519.SH|2021-04-01|2026-04-01',
    'CORPORATE_ACTION_OFFICIAL_MATCH_REQUIRED',
    case when s.action_count>0
                   and s.action_count=s.validated_action_count
                   and s.complete_official_count=s.matched_official_count
         then 'Every Moutai cash dividend in the holding window reconciles to one official implementation announcement.'
         else 'One or more Moutai cash dividends or official implementation announcements remain unmatched.' end,
    case when s.action_count>0
                   and s.action_count=s.validated_action_count
                   and s.complete_official_count=s.matched_official_count
         then 'resolved' else 'open' end,
    jsonb_build_object(
        'action_count',s.action_count,
        'complete_official_count',s.complete_official_count,
        'validated_action_count',s.validated_action_count,
        'matched_official_count',s.matched_official_count,
        'unmatched_actions',s.unmatched_actions,
        'unmatched_official_records',s.unmatched_official_records,
        'matching_version','corporate-action-official-match-v1'
    ),
    case when s.action_count>0
                   and s.action_count=s.validated_action_count
                   and s.complete_official_count=s.matched_official_count
         then now() else null end
from s
where not exists (
    select 1 from audit.data_quality_issues q
    where q.rule_code='CORPORATE_ACTION_OFFICIAL_MATCH_REQUIRED'
      and q.record_key='600519.SH|2021-04-01|2026-04-01'
  );

insert into audit.data_quality_issues
    (severity,domain,table_name,record_key,rule_code,description,status,details)
select
    'critical','corporate_action_evidence','raw.documents',
    '600519.SH|2021-04-01|2026-04-01',
    'OFFICIAL_DIVIDEND_CAPTURE_FAILED',
    'The fixed CNINFO capture did not produce official dividend implementation announcements.',
    'open',
    jsonb_build_object(
        'http_status',r.http_status,
        'response',coalesce(r.payload,to_jsonb(r.raw_content)),
        'function','capture-moutai-dividend-announcements'
    )
from _dividend_response r
where (select count(*) from _dividend_documents)=0
  and not exists (
      select 1 from audit.data_quality_issues q
      where q.rule_code='OFFICIAL_DIVIDEND_CAPTURE_FAILED'
        and q.record_key='600519.SH|2021-04-01|2026-04-01'
        and q.status='open'
  );

update audit.data_quality_issues q
set status='resolved',resolved_at=now(),
    details=q.details||jsonb_build_object(
        'resolved_by','subsequent successful CNINFO dividend capture'
    )
where q.rule_code='OFFICIAL_DIVIDEND_CAPTURE_FAILED'
  and q.record_key='600519.SH|2021-04-01|2026-04-01'
  and q.status='open'
  and (select count(*) from _dividend_documents)>0;

update raw.ingestion_batches b
set status=case when exists(select 1 from _dividend_documents)
                then 'completed' else 'failed' end,
    completed_at=now(),
    row_count=(select count(*) from _dividend_documents),
    batch_hash=(select content_hash from _dividend_manifest_document limit 1),
    error_text=case when exists(select 1 from _dividend_documents) then null
                    else left(coalesce(
                        (select payload->>'error' from _dividend_response),
                        (select raw_content from _dividend_response),
                        'CNINFO dividend capture returned no official documents'
                    ),2000) end
where b.batch_id in(select batch_id from _dividend_batch);

commit;

select * from _dividend_reconciliation;

select
    m.match_id,m.status,m.announcement_title,m.official_ex_date,
    m.official_record_date,m.official_payment_date,
    m.official_cash_amount_per_share,m.observed_ex_date,
    m.observed_record_date,m.observed_payment_date,
    m.observed_cash_amount_per_share,m.field_checks
from audit.corporate_action_matches m
order by m.official_ex_date,m.announcement_id;
