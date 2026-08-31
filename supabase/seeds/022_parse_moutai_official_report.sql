begin;

create temporary table _parse_response on commit drop as
select
    (response).status as http_status,
    (response).content as raw_content,
    case
        when ltrim((response).content) like '{%'
            then (response).content::jsonb
        else null
    end as payload
from (
    select extensions.http_post(
        'https://eqrqvyprikmwnlptzkao.supabase.co/functions/v1/parse-moutai-2020-report',
        '{}',
        'application/json'
    ) as response
) request;

create temporary table _parse_batch on commit drop as
with inserted as (
    insert into raw.ingestion_batches
        (source_id, status, adapter_version, request_params)
    select
        source_id,
        'running',
        'parse-moutai-2020-report-v1',
        jsonb_build_object(
            'function', 'parse-moutai-2020-report',
            'fixed_target', 'KWEICHOW_MOUTAI|2020_ANNUAL_REPORT',
            'purpose', 'page-level evidence index; no automatic accounting fact promotion'
        )
    from raw.data_sources
    where source_code = 'CNINFO'
    returning batch_id, source_id
)
select * from inserted;

create temporary table _official_pdf on commit drop as
select
    d.document_id,
    d.issuer_id,
    d.security_id,
    d.title,
    d.source_url,
    d.storage_uri,
    d.published_at,
    d.content_hash
from raw.documents d
join raw.data_sources s on s.source_id = d.source_id
join master.issuers i on i.issuer_id = d.issuer_id
where s.source_code = 'CNINFO'
  and i.issuer_code = 'KWEICHOW_MOUTAI'
  and d.document_type = 'official_annual_report_pdf'
  and d.content_hash is not null
order by d.retrieved_at desc, d.document_id desc
limit 1;

create temporary table _extraction_document on commit drop as
with eligible as (
    select
        r.payload,
        b.batch_id,
        b.source_id,
        p.document_id as source_pdf_document_id,
        p.issuer_id,
        p.security_id,
        p.source_url,
        p.published_at,
        p.content_hash as official_pdf_hash
    from _parse_response r
    cross join _parse_batch b
    cross join _official_pdf p
    where r.http_status = 200
      and r.payload->>'error' is null
      and length(coalesce(r.payload->>'extraction_sha256', '')) = 64
      and length(coalesce(r.payload->>'pdf_sha256', '')) = 64
      and r.payload->>'pdf_sha256' = p.content_hash
      and coalesce((r.payload->>'page_count_extracted')::integer, 0) > 0
      and jsonb_typeof(r.payload->'pages') = 'array'
      and jsonb_typeof(r.payload->'hits') = 'array'
), inserted as (
    insert into raw.documents
        (source_id, batch_id, issuer_id, security_id, document_type, title,
         source_url, storage_uri, mime_type, language, published_at,
         retrieved_at, content_hash, parser_version, metadata)
    select
        e.source_id,
        e.batch_id,
        e.issuer_id,
        e.security_id,
        'official_annual_report_extraction',
        '贵州茅台2020年年度报告页级证据索引',
        e.source_url,
        e.payload->>'extraction_storage_uri',
        'application/json',
        'zh-CN',
        e.published_at,
        coalesce(nullif(e.payload->>'extracted_at', '')::timestamptz, now()),
        e.payload->>'extraction_sha256',
        e.payload->>'parser',
        jsonb_build_object(
            'source_pdf_document_id', e.source_pdf_document_id,
            'official_pdf_hash', e.official_pdf_hash,
            'pdf_storage_uri', e.payload->>'pdf_storage_uri',
            'extraction_storage_uri', e.payload->>'extraction_storage_uri',
            'page_count_reported', e.payload->>'page_count_reported',
            'page_count_extracted', e.payload->>'page_count_extracted',
            'full_text_characters', e.payload->>'full_text_characters',
            'keyword_hit_count', e.payload->>'keyword_hit_count',
            'extraction_bytes', e.payload->>'extraction_bytes',
            'pages', e.payload->'pages',
            'methodology_quality', e.payload->>'methodology_quality',
            'formal_fact_promotion_allowed', false
        )
    from eligible e
    where not exists (
        select 1
        from raw.documents d
        where d.source_id = e.source_id
          and d.issuer_id = e.issuer_id
          and d.document_type = 'official_annual_report_extraction'
          and d.content_hash = e.payload->>'extraction_sha256'
    )
    returning document_id, batch_id, source_id, issuer_id, security_id,
              source_url, storage_uri, published_at, retrieved_at,
              content_hash, parser_version, metadata
), existing as (
    select
        d.document_id, d.batch_id, d.source_id, d.issuer_id, d.security_id,
        d.source_url, d.storage_uri, d.published_at, d.retrieved_at,
        d.content_hash, d.parser_version, d.metadata
    from raw.documents d
    join eligible e
      on d.source_id = e.source_id
     and d.issuer_id = e.issuer_id
     and d.document_type = 'official_annual_report_extraction'
     and d.content_hash = e.payload->>'extraction_sha256'
)
select * from inserted
union all
select * from existing
limit 1;

insert into raw.records
    (document_id, issuer_id, security_id, dataset_code, source_record_key,
     payload, published_at, available_at, record_hash, metadata)
select
    d.document_id,
    d.issuer_id,
    d.security_id,
    'cninfo_annual_report_page_index',
    'page|' || coalesce(page_item->>'page', ordinality::text),
    page_item,
    d.published_at,
    d.published_at,
    encode(
        extensions.digest(convert_to(page_item::text, 'UTF8'), 'sha256'),
        'hex'
    ),
    jsonb_build_object(
        'official_pdf_hash', d.metadata->>'official_pdf_hash',
        'extraction_hash', d.content_hash,
        'parser', d.parser_version,
        'record_role', 'page_index',
        'formal_fact_promotion_allowed', false
    )
from _extraction_document d
cross join _parse_response r
cross join lateral jsonb_array_elements(r.payload->'pages')
    with ordinality as pages(page_item, ordinality)
on conflict (document_id, source_record_key) do nothing;

insert into raw.records
    (document_id, issuer_id, security_id, dataset_code, source_record_key,
     payload, published_at, available_at, record_hash, metadata)
select
    d.document_id,
    d.issuer_id,
    d.security_id,
    'cninfo_annual_report_page_hit',
    concat_ws('|',
        'hit',
        coalesce(hit_item->>'page', 'unknown'),
        coalesce(hit_item->>'keyword', 'unknown'),
        ordinality::text
    ),
    hit_item,
    d.published_at,
    d.published_at,
    encode(
        extensions.digest(convert_to(hit_item::text, 'UTF8'), 'sha256'),
        'hex'
    ),
    jsonb_build_object(
        'official_pdf_hash', d.metadata->>'official_pdf_hash',
        'extraction_hash', d.content_hash,
        'parser', d.parser_version,
        'record_role', 'keyword_hit',
        'candidate_numbers_only', true,
        'formal_fact_promotion_allowed', false
    )
from _extraction_document d
cross join _parse_response r
cross join lateral jsonb_array_elements(r.payload->'hits')
    with ordinality as hits(hit_item, ordinality)
on conflict (document_id, source_record_key) do nothing;

update raw.ingestion_batches b
set status = case when exists (select 1 from _extraction_document)
                  then 'completed' else 'failed' end,
    completed_at = now(),
    row_count = case when exists (select 1 from _extraction_document)
                     then (
                         select count(*)
                         from raw.records rr
                         where rr.document_id = (
                             select document_id from _extraction_document limit 1
                         )
                     ) else 0 end,
    batch_hash = (select content_hash from _extraction_document limit 1),
    error_text = case when exists (select 1 from _extraction_document) then null
                      else left(coalesce(
                          (select payload->>'error' from _parse_response),
                          (select raw_content from _parse_response),
                          'Official PDF parser returned no eligible extraction'
                      ), 2000) end
where b.batch_id in (select batch_id from _parse_batch);

insert into audit.evidence_assertions
    (assertion_code, subject_type, subject_id, as_of_at, evidence_grade,
     status, source_codes, content_hashes, unresolved_conflict, details,
     asserted_by)
select
    'annual_report_page_evidence',
    'official_document_extraction',
    d.document_id::text,
    d.published_at,
    3,
    'active',
    array['CNINFO'],
    array_remove(array[d.metadata->>'official_pdf_hash', d.content_hash], null),
    false,
    jsonb_build_object(
        'source_url', d.source_url,
        'storage_uri', d.storage_uri,
        'parser', d.parser_version,
        'page_count_extracted', d.metadata->>'page_count_extracted',
        'keyword_hit_count', d.metadata->>'keyword_hit_count',
        'quality_reason', 'page evidence is anchored to a hashed official PDF; candidate accounting values still require review'
    ),
    'parse-moutai-2020-report-v1'
from _extraction_document d
where not exists (
    select 1
    from audit.evidence_assertions e
    where e.assertion_code = 'annual_report_page_evidence'
      and e.subject_type = 'official_document_extraction'
      and e.subject_id = d.document_id::text
      and e.status = 'active'
);

update audit.data_quality_issues q
set status = 'resolved',
    resolved_at = now(),
    details = q.details || jsonb_build_object(
        'resolved_by', 'parse-moutai-2020-report-v1',
        'extraction_document_id', (
            select document_id from _extraction_document limit 1
        ),
        'extraction_hash', (
            select content_hash from _extraction_document limit 1
        )
    )
where q.rule_code = 'OFFICIAL_PDF_PARSE_FAILED'
  and q.record_key = 'KWEICHOW_MOUTAI|2020_ANNUAL_REPORT_PDF'
  and q.status = 'open'
  and exists (select 1 from _extraction_document);

insert into audit.data_quality_issues
    (severity, domain, table_name, record_key, rule_code, description,
     status, details)
select
    'critical',
    'official_document',
    'raw.records',
    'KWEICHOW_MOUTAI|2020_ANNUAL_REPORT_PDF',
    'OFFICIAL_PDF_PARSE_FAILED',
    'The fixed server-side parser could not produce a page-level evidence index from the official annual-report PDF.',
    'open',
    jsonb_build_object(
        'http_status', r.http_status,
        'response', coalesce(r.payload, to_jsonb(r.raw_content)),
        'function', 'parse-moutai-2020-report'
    )
from _parse_response r
where not exists (select 1 from _extraction_document)
  and not exists (
      select 1
      from audit.data_quality_issues q
      where q.rule_code = 'OFFICIAL_PDF_PARSE_FAILED'
        and q.record_key = 'KWEICHOW_MOUTAI|2020_ANNUAL_REPORT_PDF'
        and q.status = 'open'
  );

insert into audit.data_quality_issues
    (severity, domain, table_name, record_key, rule_code, description,
     status, details)
select
    'info',
    'accounting_evidence_review',
    'raw.records',
    'KWEICHOW_MOUTAI|2020_ANNUAL_REPORT_PAGE_EVIDENCE',
    'OFFICIAL_PAGE_EVIDENCE_REVIEW_REQUIRED',
    'Official page-level keyword evidence is available, but candidate numbers require accounting-context review before formal fact promotion.',
    'open',
    jsonb_build_object(
        'extraction_document_id', d.document_id,
        'official_pdf_hash', d.metadata->>'official_pdf_hash',
        'extraction_hash', d.content_hash,
        'page_count_extracted', d.metadata->>'page_count_extracted',
        'keyword_hit_count', d.metadata->>'keyword_hit_count',
        'formal_fact_promotion_allowed', false
    )
from _extraction_document d
where not exists (
    select 1
    from audit.data_quality_issues q
    where q.rule_code = 'OFFICIAL_PAGE_EVIDENCE_REVIEW_REQUIRED'
      and q.record_key = 'KWEICHOW_MOUTAI|2020_ANNUAL_REPORT_PAGE_EVIDENCE'
      and q.status = 'open'
);

commit;
