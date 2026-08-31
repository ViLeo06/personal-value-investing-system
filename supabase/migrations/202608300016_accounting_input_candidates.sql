begin;

create table if not exists fundamentals.accounting_field_rules (
    rule_id bigint generated always as identity primary key,
    model_family text not null,
    input_key text not null,
    component_code text not null,
    source_field_regex text not null,
    expected_keywords text[] not null default '{}'::text[],
    sign numeric not null default 1,
    aggregation_group text,
    priority integer not null default 100,
    auto_promote boolean not null default false,
    notes text,
    enabled boolean not null default true,
    created_at timestamptz not null default now(),
    unique (model_family,input_key,component_code,source_field_regex),
    check (sign in (-1,1)),
    check (cardinality(expected_keywords)>0)
);

create table if not exists fundamentals.accounting_input_candidates (
    candidate_id uuid primary key default gen_random_uuid(),
    run_id uuid not null references model.valuation_runs(run_id),
    issuer_id uuid not null references master.issuers(issuer_id),
    rule_id bigint not null references fundamentals.accounting_field_rules(rule_id),
    input_key text not null,
    component_code text not null,
    period_end date not null,
    source_record_id bigint not null references raw.records(record_id),
    source_document_id uuid not null references raw.documents(document_id),
    dataset_code text not null,
    source_field text not null,
    source_value_text text not null,
    value_numeric numeric not null,
    sign numeric not null,
    signed_value numeric not null,
    source_record_hash text,
    status text not null default 'candidate'
        check (status in ('candidate','page_matched','validated','rejected','superseded')),
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    validated_at timestamptz,
    unique (run_id,rule_id,period_end,source_record_id,source_field),
    check (sign in (-1,1)),
    check (jsonb_typeof(metadata)='object')
);

create table if not exists audit.accounting_candidate_page_matches (
    match_id bigint generated always as identity primary key,
    candidate_id uuid not null
        references fundamentals.accounting_input_candidates(candidate_id),
    extraction_document_id uuid not null references raw.documents(document_id),
    page_hit_record_id bigint not null references raw.records(record_id),
    page_number integer,
    keyword text not null,
    source_number_text text not null,
    parsed_number numeric not null,
    scale numeric not null,
    normalized_value numeric not null,
    candidate_value numeric not null,
    absolute_difference numeric not null,
    relative_difference numeric,
    status text not null default 'candidate'
        check (status in ('candidate','validated','rejected','superseded')),
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    validated_at timestamptz,
    unique (candidate_id,page_hit_record_id,source_number_text,scale),
    check (scale>0),
    check (absolute_difference>=0),
    check (jsonb_typeof(metadata)='object')
);

create index if not exists accounting_field_rules_input_idx
    on fundamentals.accounting_field_rules(model_family,input_key,priority);
create index if not exists accounting_input_candidates_run_input_idx
    on fundamentals.accounting_input_candidates(run_id,input_key,period_end,status);
create index if not exists accounting_input_candidates_source_idx
    on fundamentals.accounting_input_candidates(source_record_id,source_field);
create index if not exists accounting_candidate_page_matches_candidate_idx
    on audit.accounting_candidate_page_matches(candidate_id,status,relative_difference);
create index if not exists accounting_candidate_page_matches_page_idx
    on audit.accounting_candidate_page_matches(extraction_document_id,page_number);

revoke all on fundamentals.accounting_field_rules from public,anon,authenticated;
revoke all on fundamentals.accounting_input_candidates from public,anon,authenticated;
revoke all on audit.accounting_candidate_page_matches from public,anon,authenticated;

commit;
