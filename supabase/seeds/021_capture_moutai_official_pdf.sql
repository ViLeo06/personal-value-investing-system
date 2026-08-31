begin;

create temporary table _capture_response on commit drop as
select
    (response).status as http_status,
    (response).content as raw_content,
    case when ltrim((response).content) like '{%'
         then (response).content::jsonb else null end as payload
from (
    select extensions.http_post(
        'https://eqrqvyprikmwnlptzkao.supabase.co/functions/v1/capture-moutai-2020-report',
        '{}',
        'application/json'
    ) as response
) request;

create temporary table _capture_batch on commit drop as
with inserted as (
    insert into raw.ingestion_batches
        (source_id,status,adapter_version,request_params)
    select
        source_id,
        'running',
        'capture-moutai-2020-report-v1',
        jsonb_build_object(
            'function','capture-moutai-2020-report',
            'fixed_target','KWEICHOW_MOUTAI|2020_ANNUAL_REPORT'
        )
    from raw.data_sources
    where source_code='CNINFO'
    returning batch_id,source_id
)
select * from inserted;

create temporary table _official_pdf_document on commit drop as
with eligible as (
    select
        r.payload,
        r.http_status,
        b.batch_id,
        b.source_id,
        i.issuer_id,
        s.security_id
    from _capture_response r
    cross join _capture_batch b
    cross join master.issuers i
    cross join master.securities s
    where i.issuer_code='KWEICHOW_MOUTAI'
      and s.security_code='600519.SH'
      and r.http_status=200
      and r.payload->>'error' is null
      and length(coalesce(r.payload->>'pdf_sha256',''))=64
      and coalesce((r.payload->>'pdf_bytes')::bigint,0)>100000
), inserted as (
    insert into raw.documents
        (source_id,batch_id,issuer_id,security_id,document_type,title,source_url,
         storage_uri,mime_type,language,published_at,retrieved_at,content_hash,
         parser_version,metadata)
    select
        e.source_id,e.batch_id,e.issuer_id,e.security_id,
        'official_annual_report_pdf',
        coalesce(e.payload->>'announcement_title','贵州茅台2020年年度报告'),
        e.payload->>'source_url',
        e.payload->>'storage_uri',
        'application/pdf','zh-CN',
        nullif(e.payload->>'published_at','')::timestamptz,
        coalesce(nullif(e.payload->>'captured_at','')::timestamptz,now()),
        e.payload->>'pdf_sha256',
        e.payload->>'capture_version',
        e.payload||jsonb_build_object(
            'evidence_status','official_pdf_hashed',
            'source_authority','official_disclosure'
        )
    from eligible e
    where not exists (
        select 1
        from raw.documents d
        where d.source_id=e.source_id
          and d.issuer_id=e.issuer_id
          and d.document_type='official_annual_report_pdf'
          and d.content_hash=e.payload->>'pdf_sha256'
    )
    returning document_id,batch_id,source_id,issuer_id,security_id,title,
              source_url,storage_uri,published_at,retrieved_at,content_hash,metadata
), existing as (
    select d.document_id,d.batch_id,d.source_id,d.issuer_id,d.security_id,d.title,
           d.source_url,d.storage_uri,d.published_at,d.retrieved_at,d.content_hash,d.metadata
    from raw.documents d
    join eligible e
      on d.source_id=e.source_id
     and d.issuer_id=e.issuer_id
     and d.document_type='official_annual_report_pdf'
     and d.content_hash=e.payload->>'pdf_sha256'
)
select * from inserted
union all
select * from existing
limit 1;

update raw.ingestion_batches b
set status=case when exists(select 1 from _official_pdf_document)
                then 'completed' else 'failed' end,
    completed_at=now(),
    row_count=(select count(*) from _official_pdf_document),
    batch_hash=(select content_hash from _official_pdf_document limit 1),
    error_text=case when exists(select 1 from _official_pdf_document) then null
                    else left(coalesce(
                        (select payload->>'error' from _capture_response),
                        (select raw_content from _capture_response),
                        'Official PDF capture returned no eligible document'
                    ),2000) end
where b.batch_id in(select batch_id from _capture_batch);

update audit.evidence_assertions e
set status='superseded'
where e.assertion_code='annual_report_publication'
  and e.subject_type='official_document'
  and e.status='active'
  and e.evidence_grade<3
  and exists(select 1 from _official_pdf_document);

insert into audit.evidence_assertions
    (assertion_code,subject_type,subject_id,as_of_at,evidence_grade,status,
     source_codes,content_hashes,unresolved_conflict,details,asserted_by)
select
    'annual_report_publication','official_document',d.document_id::text,
    d.published_at,3,'active',array['CNINFO'],array[d.content_hash],false,
    jsonb_build_object(
        'title',d.title,
        'source_url',d.source_url,
        'storage_uri',d.storage_uri,
        'pdf_bytes',d.metadata->>'pdf_bytes',
        'capture_version',d.metadata->>'capture_version',
        'quality_reason','official PDF bytes archived with SHA-256 content hash'
    ),
    'capture-moutai-2020-report-v1'
from _official_pdf_document d
where not exists (
    select 1 from audit.evidence_assertions e
    where e.assertion_code='annual_report_publication'
      and e.subject_type='official_document'
      and e.subject_id=d.document_id::text
      and e.evidence_grade=3
      and e.status='active'
);

update audit.data_quality_issues q
set status='resolved',
    resolved_at=now(),
    details=q.details||jsonb_build_object(
        'resolved_by','capture-moutai-2020-report-v1',
        'document_id',(select document_id from _official_pdf_document limit 1),
        'content_hash',(select content_hash from _official_pdf_document limit 1),
        'storage_uri',(select storage_uri from _official_pdf_document limit 1)
    )
where q.rule_code='OFFICIAL_PDF_CONTENT_HASH_REQUIRED'
  and q.record_key='KWEICHOW_MOUTAI|2020_ANNUAL_REPORT_PDF'
  and q.status='open'
  and exists(select 1 from _official_pdf_document);

insert into audit.data_quality_issues
    (severity,domain,table_name,record_key,rule_code,description,status,details)
select
    'critical','official_document','raw.documents',
    'KWEICHOW_MOUTAI|2020_ANNUAL_REPORT_PDF',
    'OFFICIAL_PDF_CAPTURE_FAILED',
    'The fixed server-side capture of the official 2020 annual-report PDF failed.',
    'open',
    jsonb_build_object(
        'http_status',r.http_status,
        'response',coalesce(r.payload,to_jsonb(r.raw_content)),
        'function','capture-moutai-2020-report'
    )
from _capture_response r
where not exists(select 1 from _official_pdf_document)
  and not exists (
      select 1 from audit.data_quality_issues q
      where q.rule_code='OFFICIAL_PDF_CAPTURE_FAILED'
        and q.record_key='KWEICHOW_MOUTAI|2020_ANNUAL_REPORT_PDF'
        and q.status='open'
  );

update audit.data_quality_issues q
set status='resolved',resolved_at=now(),
    details=q.details||jsonb_build_object(
        'resolved_by','subsequent successful Edge Function capture'
    )
where q.rule_code='OFFICIAL_PDF_CAPTURE_FAILED'
  and q.record_key='KWEICHOW_MOUTAI|2020_ANNUAL_REPORT_PDF'
  and q.status='open'
  and exists(select 1 from _official_pdf_document);

commit;
