begin;

create table if not exists audit.corporate_action_matches (
    match_id uuid primary key default gen_random_uuid(),
    action_id uuid not null references pit.corporate_actions(action_id),
    official_document_id uuid not null references raw.documents(document_id),
    official_record_id bigint not null references raw.records(record_id),
    announcement_id text not null,
    announcement_title text not null,
    official_published_at timestamptz,
    official_ex_date date,
    official_record_date date,
    official_payment_date date,
    official_cash_amount_per_share numeric,
    official_currency text,
    observed_ex_date date,
    observed_record_date date,
    observed_payment_date date,
    observed_cash_amount_per_share numeric,
    observed_currency text,
    date_difference_days integer,
    amount_difference numeric,
    field_checks jsonb not null default '{}'::jsonb,
    status text not null default 'candidate'
        check (status in ('candidate','validated','conflict','rejected','superseded')),
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    validated_at timestamptz,
    unique (action_id,official_document_id),
    check (amount_difference is null or amount_difference>=0),
    check (jsonb_typeof(field_checks)='object'),
    check (jsonb_typeof(metadata)='object')
);

create index if not exists corporate_action_matches_action_status_idx
    on audit.corporate_action_matches(action_id,status);
create index if not exists corporate_action_matches_document_idx
    on audit.corporate_action_matches(official_document_id);
create index if not exists corporate_action_matches_announcement_idx
    on audit.corporate_action_matches(announcement_id,status);
create index if not exists corporate_action_matches_dates_idx
    on audit.corporate_action_matches(official_ex_date,observed_ex_date);

revoke all on audit.corporate_action_matches
    from public,anon,authenticated;

commit;
