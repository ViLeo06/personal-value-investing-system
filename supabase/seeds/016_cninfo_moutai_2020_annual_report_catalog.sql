begin;

with source_row as (
    select source_id
    from raw.data_sources
    where source_code='CNINFO'
), issuer_row as (
    select issuer_id
    from master.issuers
    where issuer_code='KWEICHOW_MOUTAI'
), security_row as (
    select security_id
    from master.securities
    where security_code='600519.SH'
), batch_row as (
    insert into raw.ingestion_batches
        (source_id,status,adapter_version,request_params)
    select
        source_row.source_id,
        'running',
        'cninfo-announcement-catalog-v1',
        jsonb_build_object(
            'stock','600519,gssh0600519',
            'category','category_ndbg_szsh',
            'date_range','2021-03-01~2021-04-30'
        )
    from source_row
    returning batch_id,source_id
), response as (
    select extensions.http_post(
        'https://www.cninfo.com.cn/new/hisAnnouncement/query',
        'pageNum=1&pageSize=30&column=sse&tabName=fulltext&plate=sh&stock=600519%2Cgssh0600519&searchkey=&secid=&category=category_ndbg_szsh%3B&trade=&seDate=2021-03-01~2021-04-30&sortName=&sortType=&isHLtitle=true',
        'application/x-www-form-urlencoded; charset=UTF-8'
    ) as r
), checked as (
    select
        (r).status as http_status,
        case when (r).status=200 then (r).content::jsonb end as payload
    from response
), announcements as (
    select
        item,
        regexp_replace(coalesce(item->>'announcementTitle',''),'<[^>]+>','','g') as clean_title
    from checked
    cross join lateral jsonb_array_elements(
        coalesce(checked.payload->'announcements','[]'::jsonb)
    ) as a(item)
    where checked.http_status=200
), selected as (
    select *
    from announcements
    where clean_title like '%2020年年度报告%'
      and clean_title not like '%摘要%'
      and clean_title not like '%英文%'
      and clean_title not like '%更正%'
      and clean_title not like '%修订%'
    order by coalesce((item->>'announcementTime')::bigint,0)
    limit 1
), inserted_document as (
    insert into raw.documents
        (source_id,batch_id,issuer_id,security_id,document_type,title,source_url,
         mime_type,language,published_at,retrieved_at,content_hash,parser_version,metadata)
    select
        batch_row.source_id,
        batch_row.batch_id,
        issuer_row.issuer_id,
        security_row.security_id,
        'official_annual_report_catalog_record',
        selected.clean_title,
        'https://static.cninfo.com.cn/'||ltrim(selected.item->>'adjunctUrl','/'),
        'application/pdf',
        'zh-CN',
        to_timestamp((selected.item->>'announcementTime')::numeric/1000.0),
        now(),
        null,
        'cninfo-announcement-catalog-v1',
        jsonb_build_object(
            'announcement_id',selected.item->>'announcementId',
            'announcement_time_epoch_ms',selected.item->>'announcementTime',
            'adjunct_url',selected.item->>'adjunctUrl',
            'catalog_record',selected.item,
            'catalog_http_status',(select http_status from checked),
            'evidence_status','official_catalog_only_pdf_hash_pending'
        )
    from selected
    cross join batch_row
    cross join issuer_row
    cross join security_row
    where not exists (
        select 1 from raw.documents d
        where d.source_id=batch_row.source_id
          and d.issuer_id=issuer_row.issuer_id
          and d.document_type='official_annual_report_catalog_record'
          and d.metadata->>'announcement_id'=selected.item->>'announcementId'
    )
    returning document_id,batch_id,source_id,issuer_id,security_id,title,source_url,published_at
), target_document as (
    select document_id,batch_id,source_id,issuer_id,security_id,title,source_url,published_at
    from inserted_document
    union all
    select d.document_id,d.batch_id,d.source_id,d.issuer_id,d.security_id,d.title,d.source_url,d.published_at
    from raw.documents d
    join source_row s on s.source_id=d.source_id
    join issuer_row i on i.issuer_id=d.issuer_id
    where d.document_type='official_annual_report_catalog_record'
      and d.metadata->>'announcement_id'=(select item->>'announcementId' from selected)
    order by document_id
    limit 1
)
insert into audit.evidence_assertions
    (assertion_code,subject_type,subject_id,as_of_at,evidence_grade,status,
     source_codes,content_hashes,unresolved_conflict,details,asserted_by)
select
    'annual_report_publication',
    'official_document',
    t.document_id::text,
    t.published_at,
    2,
    'active',
    array['CNINFO'],
    '{}'::text[],
    false,
    jsonb_build_object(
        'title',t.title,
        'source_url',t.source_url,
        'quality_reason','official catalog metadata confirmed; PDF content hash pending'
    ),
    'cninfo-announcement-catalog-v1'
from target_document t
where not exists (
    select 1 from audit.evidence_assertions e
    where e.assertion_code='annual_report_publication'
      and e.subject_type='official_document'
      and e.subject_id=t.document_id::text
      and e.status='active'
);

with batch_target as (
    select batch_id from batch_row
), selected_count as (
    select count(*) as n from selected
)
update raw.ingestion_batches b
set status=case when selected_count.n=1 then 'completed' else 'failed' end,
    completed_at=now(),
    row_count=selected_count.n,
    error_text=case when selected_count.n=1 then null else 'CNINFO annual-report catalog record was not found' end
from selected_count
where b.batch_id in(select batch_id from batch_target);

insert into audit.data_quality_issues
    (severity,domain,table_name,record_key,rule_code,description,status,details)
select
    'warning','official_document','raw.documents',
    'KWEICHOW_MOUTAI|2020_ANNUAL_REPORT_PDF',
    'OFFICIAL_PDF_CONTENT_HASH_REQUIRED',
    'The official CNINFO announcement catalog record is available, but the PDF bytes and content hash must be captured before page-level facts can receive primary-evidence grade.',
    'open',
    jsonb_build_object(
        'document_id',t.document_id,
        'source_url',t.source_url,
        'published_at',t.published_at,
        'required','download PDF, compute SHA-256, build page-level evidence index'
    )
from target_document t
where not exists (
    select 1 from audit.data_quality_issues q
    where q.rule_code='OFFICIAL_PDF_CONTENT_HASH_REQUIRED'
      and q.record_key='KWEICHOW_MOUTAI|2020_ANNUAL_REPORT_PDF'
      and q.status='open'
);

commit;
