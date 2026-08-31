begin;

with requests(dataset_code, report_name, source_url) as (
    values
        ('eastmoney_sharebonus_det'::text,'RPT_SHAREBONUS_DET'::text,
         'https://datacenter-web.eastmoney.com/api/data/v1/get?reportName=RPT_SHAREBONUS_DET&columns=ALL&filter=(SECURITY_CODE%3D%22600519%22)&pageNumber=1&pageSize=500&sortTypes=-1&sortColumns=REPORT_DATE'::text),
        ('eastmoney_f10_dividend'::text,'RPT_F10_DIVIDEND'::text,
         'https://datacenter-web.eastmoney.com/api/data/v1/get?reportName=RPT_F10_DIVIDEND&columns=ALL&filter=(SECURITY_CODE%3D%22600519%22)&pageNumber=1&pageSize=500&sortTypes=-1&sortColumns=REPORT_DATE'::text),
        ('eastmoney_f10_bonusfinance'::text,'RPT_F10_BONUSFINANCE'::text,
         'https://datacenter-web.eastmoney.com/api/data/v1/get?reportName=RPT_F10_BONUSFINANCE&columns=ALL&filter=(SECURITY_CODE%3D%22600519%22)&pageNumber=1&pageSize=500&sortTypes=-1&sortColumns=REPORT_DATE'::text)
), source_row as (
    select source_id
    from raw.data_sources
    where source_code='AKSHARE_EASTMONEY_FINANCIAL'
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
        'eastmoney-dividend-discovery-v1',
        jsonb_build_object(
            'security_code','600519',
            'report_names',jsonb_build_array(
                'RPT_SHAREBONUS_DET','RPT_F10_DIVIDEND','RPT_F10_BONUSFINANCE'
            )
        )
    from source_row
    returning batch_id,source_id
), responses as (
    select
        r.dataset_code,
        r.report_name,
        r.source_url,
        extensions.http_get(r.source_url) as response
    from requests r
), checked as (
    select
        dataset_code,report_name,source_url,
        (response).status as http_status,
        (response).content::jsonb as payload
    from responses
), documents as (
    insert into raw.documents
        (source_id,batch_id,issuer_id,security_id,document_type,title,source_url,
         mime_type,language,retrieved_at,content_hash,parser_version,metadata)
    select
        batch_row.source_id,
        batch_row.batch_id,
        issuer_row.issuer_id,
        security_row.security_id,
        'corporate_action_api_response',
        '600519 dividend discovery '||checked.report_name,
        checked.source_url,
        'application/json',
        'zh-CN',
        now(),
        encode(extensions.digest(convert_to(checked.payload::text,'UTF8'),'sha256'),'hex'),
        'eastmoney-dividend-discovery-v1',
        jsonb_build_object(
            'dataset_code',checked.dataset_code,
            'report_name',checked.report_name,
            'http_status',checked.http_status,
            'provider_payload',checked.payload,
            'methodology_quality','candidate_requires_official_announcement'
        )
    from checked
    cross join batch_row
    cross join issuer_row
    cross join security_row
    where checked.http_status=200
      and jsonb_typeof(checked.payload->'result'->'data')='array'
      and jsonb_array_length(checked.payload->'result'->'data')>0
    returning document_id,batch_id,issuer_id,security_id,metadata
), rows_to_insert as (
    select
        d.document_id,d.batch_id,d.issuer_id,d.security_id,
        d.metadata->>'dataset_code' as dataset_code,
        row_payload,
        concat_ws('|',
            coalesce(row_payload->>'SECURITY_CODE','600519'),
            coalesce(row_payload->>'REPORT_DATE',row_payload->>'NOTICE_DATE','unknown'),
            row_number() over (
                partition by d.document_id
                order by coalesce(row_payload->>'REPORT_DATE',''),
                         coalesce(row_payload->>'NOTICE_DATE',''),
                         row_payload::text
            )
        ) as source_record_key
    from documents d
    join checked c on c.dataset_code=d.metadata->>'dataset_code'
    cross join lateral jsonb_array_elements(c.payload->'result'->'data') as r(row_payload)
), inserted as (
    insert into raw.records
        (document_id,issuer_id,security_id,dataset_code,source_record_key,payload,
         published_at,available_at,record_hash,metadata)
    select
        r.document_id,r.issuer_id,r.security_id,r.dataset_code,r.source_record_key,
        r.row_payload,null,null,
        encode(extensions.digest(convert_to(r.row_payload::text,'UTF8'),'sha256'),'hex'),
        jsonb_build_object(
            'notice_date_raw',r.row_payload->>'NOTICE_DATE',
            'report_date_raw',r.row_payload->>'REPORT_DATE',
            'pit_status','unvalidated',
            'field_count',jsonb_object_length(r.row_payload)
        )
    from rows_to_insert r
    on conflict (document_id,source_record_key) do nothing
    returning record_id
)
update raw.ingestion_batches b
set status=case when exists(select 1 from inserted) then 'completed' else 'failed' end,
    completed_at=now(),
    row_count=(select count(*) from inserted),
    batch_hash=(
        select encode(
            extensions.digest(
                convert_to(string_agg(record_id::text,'|' order by record_id),'UTF8'),
                'sha256'
            ),'hex'
        )
        from inserted
    ),
    error_text=case when exists(select 1 from inserted) then null else 'No dividend candidate rows returned' end
where b.batch_id in(select batch_id from batch_row);

with fields as (
    select distinct
        r.dataset_code,
        e.key as source_field
    from raw.records r
    join master.securities s on s.security_id=r.security_id
    cross join lateral jsonb_each(r.payload) e
    where s.security_code='600519.SH'
      and r.dataset_code like 'eastmoney_%dividend%'
         or (s.security_code='600519.SH' and r.dataset_code='eastmoney_sharebonus_det')
      and e.key ~* '(DIVIDEND|BONUS|CASH|EX_|RECORD|PAY|DATE|RATIO|TAX|IMPLEMENT|PLAN)'
), packed as (
    select jsonb_agg(
        jsonb_build_object('dataset_code',dataset_code,'source_field',source_field)
        order by dataset_code,source_field
    ) as candidates
    from fields
)
insert into audit.data_quality_issues
    (severity,domain,table_name,record_key,rule_code,description,status,details)
select
    'info','corporate_action_mapping','raw.records',
    '600519.SH|DIVIDEND_FIELDS',
    'CORPORATE_ACTION_FIELD_MAPPING_REVIEW_REQUIRED',
    'Dividend endpoint and field candidates require official-announcement validation before corporate-action facts are admitted.',
    'open',
    jsonb_build_object(
        'field_candidates',coalesce(packed.candidates,'[]'::jsonb),
        'formal_use_allowed',false
    )
from packed
where not exists(
    select 1 from audit.data_quality_issues q
    where q.rule_code='CORPORATE_ACTION_FIELD_MAPPING_REVIEW_REQUIRED'
      and q.record_key='600519.SH|DIVIDEND_FIELDS'
      and q.status='open'
);

commit;
