begin;

insert into raw.data_sources
    (source_code, name, source_type, homepage_url, is_free, is_open_source,
     pit_capability, priority, notes)
values
    ('AKSHARE_EASTMONEY_FINANCIAL',
     'AKShare / Eastmoney financial statement adapter',
     'open_source_adapter',
     'https://github.com/akfamily/akshare',
     true,
     true,
     'derived',
     60,
     'Raw financial rows are retained as evidence candidates. Formal PIT facts require official-disclosure date and field-mapping validation.')
on conflict (source_code) do update
set name = excluded.name,
    source_type = excluded.source_type,
    homepage_url = excluded.homepage_url,
    is_free = excluded.is_free,
    is_open_source = excluded.is_open_source,
    pit_capability = excluded.pit_capability,
    priority = excluded.priority,
    notes = excluded.notes;

with requests(dataset_code, source_url) as (
    values
        ('eastmoney_balance'::text,
         'https://datacenter-web.eastmoney.com/api/data/v1/get?reportName=RPT_DMSK_FN_BALANCE&columns=ALL&filter=(SECURITY_CODE%3D%22600519%22)(REPORT_DATE%3D%272020-12-31%27)&pageNumber=1&pageSize=50&sortTypes=-1&sortColumns=REPORT_DATE'::text),
        ('eastmoney_income'::text,
         'https://datacenter-web.eastmoney.com/api/data/v1/get?reportName=RPT_DMSK_FN_INCOME&columns=ALL&filter=(SECURITY_CODE%3D%22600519%22)(REPORT_DATE%3D%272020-12-31%27)&pageNumber=1&pageSize=50&sortTypes=-1&sortColumns=REPORT_DATE'::text),
        ('eastmoney_cashflow'::text,
         'https://datacenter-web.eastmoney.com/api/data/v1/get?reportName=RPT_DMSK_FN_CASHFLOW&columns=ALL&filter=(SECURITY_CODE%3D%22600519%22)(REPORT_DATE%3D%272020-12-31%27)&pageNumber=1&pageSize=50&sortTypes=-1&sortColumns=REPORT_DATE'::text)
), source_row as (
    select source_id
    from raw.data_sources
    where source_code = 'AKSHARE_EASTMONEY_FINANCIAL'
), issuer_row as (
    select issuer_id
    from master.issuers
    where issuer_code = 'KWEICHOW_MOUTAI'
), security_row as (
    select security_id
    from master.securities
    where security_code = '600519.SH'
), batch_row as (
    insert into raw.ingestion_batches
        (source_id, status, adapter_version, request_params)
    select
        source_row.source_id,
        'running',
        'eastmoney-financial-v1',
        jsonb_build_object(
            'security_code','600519',
            'report_date','2020-12-31',
            'datasets',jsonb_build_array('balance','income','cashflow')
        )
    from source_row
    returning batch_id, source_id
), responses as (
    select
        requests.dataset_code,
        requests.source_url,
        extensions.http_get(requests.source_url) as response
    from requests
), checked as (
    select
        dataset_code,
        source_url,
        (response).status as http_status,
        (response).content::jsonb as payload
    from responses
), documents as (
    insert into raw.documents
        (source_id, batch_id, issuer_id, security_id, document_type, title,
         source_url, mime_type, language, retrieved_at, content_hash,
         parser_version, metadata)
    select
        batch_row.source_id,
        batch_row.batch_id,
        issuer_row.issuer_id,
        security_row.security_id,
        'financial_api_response',
        '600519 2020-12-31 ' || checked.dataset_code,
        checked.source_url,
        'application/json',
        'zh-CN',
        now(),
        encode(extensions.digest(convert_to(checked.payload::text,'UTF8'),'sha256'),'hex'),
        'eastmoney-financial-v1',
        jsonb_build_object(
            'dataset_code',checked.dataset_code,
            'http_status',checked.http_status,
            'provider_payload',checked.payload,
            'methodology_quality','raw_candidate_not_yet_pit_validated'
        )
    from checked
    cross join source_row
    cross join issuer_row
    cross join security_row
    cross join batch_row
    where checked.http_status = 200
      and jsonb_typeof(checked.payload->'result'->'data') = 'array'
      and jsonb_array_length(checked.payload->'result'->'data') > 0
    returning document_id, batch_id, issuer_id, security_id, metadata
), rows_to_insert as (
    select
        documents.document_id,
        documents.batch_id,
        documents.issuer_id,
        documents.security_id,
        documents.metadata->>'dataset_code' as dataset_code,
        row_payload,
        concat_ws('|',
            coalesce(row_payload->>'SECURITY_CODE','600519'),
            coalesce(row_payload->>'REPORT_DATE','2020-12-31'),
            coalesce(row_payload->>'REPORT_TYPE',row_payload->>'REPORT_DATE_NAME','unknown'),
            row_number() over (
                partition by documents.document_id
                order by coalesce(row_payload->>'NOTICE_DATE',''), row_payload::text
            )
        ) as source_record_key
    from documents
    join checked
      on checked.dataset_code = documents.metadata->>'dataset_code'
    cross join lateral jsonb_array_elements(checked.payload->'result'->'data') as r(row_payload)
), inserted_records as (
    insert into raw.records
        (document_id, issuer_id, security_id, dataset_code, source_record_key,
         payload, published_at, available_at, record_hash, metadata)
    select
        rows_to_insert.document_id,
        rows_to_insert.issuer_id,
        rows_to_insert.security_id,
        rows_to_insert.dataset_code,
        rows_to_insert.source_record_key,
        rows_to_insert.row_payload,
        null,
        null,
        encode(
            extensions.digest(convert_to(rows_to_insert.row_payload::text,'UTF8'),'sha256'),
            'hex'
        ),
        jsonb_build_object(
            'notice_date_raw',rows_to_insert.row_payload->>'NOTICE_DATE',
            'report_date_raw',rows_to_insert.row_payload->>'REPORT_DATE',
            'pit_status','unvalidated',
            'field_count',jsonb_object_length(rows_to_insert.row_payload)
        )
    from rows_to_insert
    on conflict (document_id, source_record_key) do nothing
    returning record_id
)
update raw.ingestion_batches b
set status = case when exists (select 1 from inserted_records) then 'completed' else 'failed' end,
    completed_at = now(),
    row_count = (select count(*) from inserted_records),
    batch_hash = (
        select encode(
            extensions.digest(
                convert_to(string_agg(record_id::text,'|' order by record_id),'UTF8'),
                'sha256'
            ),
            'hex'
        )
        from inserted_records
    ),
    error_text = case when exists (select 1 from inserted_records) then null else 'No eligible financial rows returned' end
where b.batch_id in (select batch_id from batch_row);

commit;
