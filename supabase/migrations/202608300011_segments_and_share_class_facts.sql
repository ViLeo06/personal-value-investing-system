begin;

create table master.business_segments (
    segment_id uuid primary key default gen_random_uuid(),
    issuer_id uuid not null references master.issuers(issuer_id),
    segment_code text not null,
    segment_name text not null,
    valid_from date not null,
    valid_to date,
    parent_segment_id uuid references master.business_segments(segment_id),
    source_document_id uuid references raw.documents(document_id),
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    constraint business_segments_validity_check
        check (valid_to is null or valid_to >= valid_from),
    unique (issuer_id, segment_code, valid_from)
);

create table pit.segment_facts (
    segment_fact_id bigint generated always as identity primary key,
    issuer_id uuid not null references master.issuers(issuer_id),
    segment_id uuid not null references master.business_segments(segment_id),
    metric_code text not null,
    period_start date,
    period_end date not null,
    fact_kind text not null default 'duration'
        check (fact_kind in ('duration','instant','other')),
    value_numeric numeric,
    value_text text,
    unit text,
    currency text,
    scale numeric not null default 1 check (scale > 0),
    published_at timestamptz,
    available_at timestamptz not null,
    ingested_at timestamptz not null default now(),
    revision_no integer not null default 1 check (revision_no > 0),
    source_document_id uuid references raw.documents(document_id),
    source_fact_key text,
    record_hash text,
    metadata jsonb not null default '{}'::jsonb,
    constraint segment_facts_one_value_check
        check (num_nonnulls(value_numeric,value_text)=1)
);

create unique index segment_facts_record_hash_uq
    on pit.segment_facts(record_hash)
    where record_hash is not null;
create index segment_facts_asof_idx
    on pit.segment_facts(issuer_id,segment_id,metric_code,period_end,available_at desc);

create table pit.share_class_facts (
    share_fact_id bigint generated always as identity primary key,
    issuer_id uuid not null references master.issuers(issuer_id),
    security_id uuid references master.securities(security_id),
    share_class_code text not null,
    period_end date not null,
    shares_outstanding numeric not null check (shares_outstanding >= 0),
    diluted_shares numeric check (diluted_shares is null or diluted_shares >= 0),
    economic_rights_multiplier numeric not null default 1
        check (economic_rights_multiplier > 0),
    voting_rights_multiplier numeric
        check (voting_rights_multiplier is null or voting_rights_multiplier >= 0),
    published_at timestamptz,
    available_at timestamptz not null,
    ingested_at timestamptz not null default now(),
    revision_no integer not null default 1 check (revision_no > 0),
    source_document_id uuid references raw.documents(document_id),
    source_fact_key text,
    record_hash text,
    metadata jsonb not null default '{}'::jsonb
);

create unique index share_class_facts_record_hash_uq
    on pit.share_class_facts(record_hash)
    where record_hash is not null;
create index share_class_facts_asof_idx
    on pit.share_class_facts(issuer_id,share_class_code,period_end,available_at desc);
create index share_class_facts_security_idx
    on pit.share_class_facts(security_id,period_end,available_at desc);

create table fundamentals.normalized_segment_facts (
    normalized_segment_fact_id bigint generated always as identity primary key,
    issuer_id uuid not null references master.issuers(issuer_id),
    segment_id uuid not null references master.business_segments(segment_id),
    metric_code text not null,
    period_start date,
    period_end date not null,
    value_numeric numeric,
    value_text text,
    unit text,
    currency text,
    normalization_version text not null,
    available_at timestamptz not null,
    record_hash text,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    constraint normalized_segment_facts_one_value_check
        check (num_nonnulls(value_numeric,value_text)=1)
);

create unique index normalized_segment_facts_record_hash_uq
    on fundamentals.normalized_segment_facts(record_hash)
    where record_hash is not null;
create index normalized_segment_facts_asof_idx
    on fundamentals.normalized_segment_facts(
        issuer_id,segment_id,metric_code,period_end,available_at desc
    );

revoke all privileges on master.business_segments,
    pit.segment_facts,
    pit.share_class_facts,
    fundamentals.normalized_segment_facts from anon, authenticated;
revoke all privileges on sequences
    pit.segment_facts_segment_fact_id_seq,
    pit.share_class_facts_share_fact_id_seq,
    fundamentals.normalized_segment_facts_normalized_segment_fact_id_seq
    from anon, authenticated;

commit;
