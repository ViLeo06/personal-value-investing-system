begin;

create table if not exists raw.records (
    record_id bigserial primary key,
    document_id uuid not null references raw.documents(document_id),
    issuer_id uuid references master.issuers(issuer_id),
    security_id uuid references master.securities(security_id),
    dataset_code text not null,
    source_record_key text not null,
    payload jsonb not null,
    published_at timestamptz,
    available_at timestamptz,
    ingested_at timestamptz not null default now(),
    record_hash text not null,
    metadata jsonb not null default '{}'::jsonb,
    unique (document_id, source_record_key),
    check (jsonb_typeof(payload) = 'object')
);

create index if not exists raw_records_issuer_dataset_idx
    on raw.records(issuer_id, dataset_code, available_at);
create index if not exists raw_records_security_dataset_idx
    on raw.records(security_id, dataset_code, available_at);
create index if not exists raw_records_hash_idx
    on raw.records(record_hash);

create table if not exists fundamentals.source_metric_mappings (
    mapping_id bigserial primary key,
    source_id uuid not null references raw.data_sources(source_id),
    dataset_code text not null,
    source_field text not null,
    metric_code text not null references fundamentals.metric_definitions(metric_code),
    statement_type text not null,
    value_type text not null default 'numeric',
    unit text,
    currency_field text,
    scale numeric not null default 1,
    sign_multiplier numeric not null default 1,
    valid_from date,
    valid_to date,
    mapping_version text not null,
    status text not null default 'candidate'
        check (status in ('candidate','validated','deprecated','rejected')),
    transform jsonb not null default '{}'::jsonb,
    notes text,
    created_at timestamptz not null default now(),
    unique (source_id, dataset_code, source_field, mapping_version),
    check (valid_to is null or valid_from is null or valid_to >= valid_from),
    check (value_type in ('numeric','text','date','boolean'))
);

create index if not exists source_metric_mappings_metric_idx
    on fundamentals.source_metric_mappings(metric_code, status);

revoke all on raw.records from public, anon, authenticated;
revoke all on fundamentals.source_metric_mappings from public, anon, authenticated;
revoke usage, select on sequence raw.records_record_id_seq from public, anon, authenticated;
revoke usage, select on sequence fundamentals.source_metric_mappings_mapping_id_seq from public, anon, authenticated;

commit;
