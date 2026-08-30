begin;

-- V1.2 central research schemas. These are intentionally not Data API schemas.
create schema if not exists master;
create schema if not exists raw;
create schema if not exists pit;
create schema if not exists fundamentals;
create schema if not exists model;
create schema if not exists backtest;
create schema if not exists audit;

revoke all on schema master, raw, pit, fundamentals, model, backtest, audit from public;
revoke all on schema master, raw, pit, fundamentals, model, backtest, audit from anon, authenticated;

-- ---------------------------------------------------------------------------
-- MASTER: stable identities and market structure
-- ---------------------------------------------------------------------------
create table master.issuers (
    issuer_id uuid primary key default gen_random_uuid(),
    issuer_code text not null unique,
    legal_name text not null,
    short_name text,
    jurisdiction text,
    sector text,
    industry text,
    reporting_currency text,
    fiscal_year_end_month smallint check (fiscal_year_end_month between 1 and 12),
    fiscal_year_end_day smallint check (fiscal_year_end_day between 1 and 31),
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table master.securities (
    security_id uuid primary key default gen_random_uuid(),
    issuer_id uuid not null references master.issuers(issuer_id),
    security_code text not null unique,
    exchange_mic text not null,
    ticker text not null,
    share_class text,
    security_type text not null default 'equity',
    quote_currency text not null,
    listing_date date,
    delisting_date date,
    is_primary_listing boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (delisting_date is null or listing_date is null or delisting_date >= listing_date)
);

create index securities_issuer_idx on master.securities(issuer_id);
create index securities_exchange_ticker_idx on master.securities(exchange_mic, ticker);

create table master.security_identifiers (
    identifier_id bigint generated always as identity primary key,
    security_id uuid not null references master.securities(security_id),
    identifier_type text not null,
    identifier_value text not null,
    valid_from date,
    valid_to date,
    source_note text,
    created_at timestamptz not null default now(),
    check (valid_to is null or valid_from is null or valid_to >= valid_from)
);

create index security_identifiers_lookup_idx
    on master.security_identifiers(identifier_type, identifier_value, valid_from, valid_to);

create table master.trading_days (
    exchange_mic text not null,
    trade_date date not null,
    is_open boolean not null,
    settlement_date date,
    source_note text,
    primary key (exchange_mic, trade_date)
);

-- ---------------------------------------------------------------------------
-- RAW / EVIDENCE: source registry and immutable evidence references
-- ---------------------------------------------------------------------------
create table raw.data_sources (
    source_id uuid primary key default gen_random_uuid(),
    source_code text not null unique,
    name text not null,
    source_type text not null,
    homepage_url text,
    license_name text,
    license_url text,
    terms_url text,
    is_free boolean not null default true,
    is_open_source boolean not null default false,
    pit_capability text not null default 'unknown'
        check (pit_capability in ('native', 'derived', 'none', 'unknown')),
    priority smallint not null default 100,
    notes text,
    created_at timestamptz not null default now()
);

create table raw.ingestion_batches (
    batch_id uuid primary key default gen_random_uuid(),
    source_id uuid not null references raw.data_sources(source_id),
    started_at timestamptz not null default now(),
    completed_at timestamptz,
    status text not null default 'running'
        check (status in ('running', 'succeeded', 'failed', 'partial')),
    adapter_version text,
    request_params jsonb not null default '{}'::jsonb,
    row_count bigint,
    batch_hash text,
    error_text text,
    check (completed_at is null or completed_at >= started_at)
);

create table raw.documents (
    document_id uuid primary key default gen_random_uuid(),
    source_id uuid not null references raw.data_sources(source_id),
    batch_id uuid references raw.ingestion_batches(batch_id),
    issuer_id uuid references master.issuers(issuer_id),
    security_id uuid references master.securities(security_id),
    document_type text not null,
    title text,
    source_url text,
    storage_uri text,
    mime_type text,
    language text,
    published_at timestamptz,
    retrieved_at timestamptz not null default now(),
    effective_date date,
    content_hash text,
    parser_version text,
    metadata jsonb not null default '{}'::jsonb
);

create index documents_issuer_published_idx on raw.documents(issuer_id, published_at desc);
create index documents_security_published_idx on raw.documents(security_id, published_at desc);
create unique index documents_content_hash_uq on raw.documents(content_hash) where content_hash is not null;

-- ---------------------------------------------------------------------------
-- PIT: facts exactly as knowable at a historical decision time
-- ---------------------------------------------------------------------------
create table pit.financial_facts (
    fact_id bigint generated always as identity primary key,
    issuer_id uuid not null references master.issuers(issuer_id),
    statement_scope text not null default 'consolidated',
    statement_type text not null,
    metric_code text not null,
    metric_label text,
    period_start date,
    period_end date not null,
    fiscal_year integer,
    fiscal_period text,
    fact_kind text not null default 'duration'
        check (fact_kind in ('instant', 'duration', 'other')),
    value_numeric numeric,
    value_text text,
    unit text,
    currency text,
    scale numeric not null default 1,
    published_at timestamptz,
    available_at timestamptz not null,
    ingested_at timestamptz not null default now(),
    revision_no integer not null default 1 check (revision_no >= 1),
    is_preliminary boolean not null default false,
    source_document_id uuid references raw.documents(document_id),
    source_fact_key text,
    record_hash text,
    metadata jsonb not null default '{}'::jsonb,
    check (period_start is null or period_start <= period_end),
    check (published_at is null or available_at >= published_at)
);

create index financial_facts_asof_idx
    on pit.financial_facts(issuer_id, metric_code, period_end, available_at desc, revision_no desc);
create index financial_facts_available_idx on pit.financial_facts(available_at);
create unique index financial_facts_record_hash_uq
    on pit.financial_facts(record_hash) where record_hash is not null;

create table pit.market_bars (
    bar_id bigint generated always as identity primary key,
    security_id uuid not null references master.securities(security_id),
    trade_date date not null,
    open_price numeric,
    high_price numeric,
    low_price numeric,
    close_price numeric,
    previous_close numeric,
    volume numeric,
    turnover numeric,
    trading_status text,
    currency text not null,
    available_at timestamptz not null,
    ingested_at timestamptz not null default now(),
    source_id uuid not null references raw.data_sources(source_id),
    batch_id uuid references raw.ingestion_batches(batch_id),
    record_hash text,
    metadata jsonb not null default '{}'::jsonb,
    unique (security_id, trade_date, source_id)
);

create index market_bars_security_date_idx on pit.market_bars(security_id, trade_date);
create index market_bars_available_idx on pit.market_bars(available_at);

create table pit.corporate_actions (
    action_id uuid primary key default gen_random_uuid(),
    security_id uuid not null references master.securities(security_id),
    action_type text not null,
    announced_at timestamptz,
    available_at timestamptz not null,
    ex_date date,
    record_date date,
    payment_date date,
    effective_date date,
    cash_amount_per_share numeric,
    currency text,
    ratio_numerator numeric,
    ratio_denominator numeric,
    subscription_price numeric,
    source_document_id uuid references raw.documents(document_id),
    record_hash text,
    metadata jsonb not null default '{}'::jsonb
);

create index corporate_actions_security_date_idx
    on pit.corporate_actions(security_id, coalesce(ex_date, effective_date, record_date));
create unique index corporate_actions_record_hash_uq
    on pit.corporate_actions(record_hash) where record_hash is not null;

create table pit.fx_rates (
    fx_id bigint generated always as identity primary key,
    base_currency text not null,
    quote_currency text not null,
    rate_date date not null,
    rate_type text not null default 'close',
    rate numeric not null,
    available_at timestamptz not null,
    source_id uuid not null references raw.data_sources(source_id),
    batch_id uuid references raw.ingestion_batches(batch_id),
    unique (base_currency, quote_currency, rate_date, rate_type, source_id)
);

create index fx_rates_asof_idx
    on pit.fx_rates(base_currency, quote_currency, rate_date, available_at desc);

create table pit.macro_observations (
    observation_id bigint generated always as identity primary key,
    series_code text not null,
    observation_date date not null,
    value numeric not null,
    unit text,
    published_at timestamptz,
    available_at timestamptz not null,
    source_id uuid not null references raw.data_sources(source_id),
    batch_id uuid references raw.ingestion_batches(batch_id),
    metadata jsonb not null default '{}'::jsonb,
    check (published_at is null or available_at >= published_at),
    unique (series_code, observation_date, available_at, source_id)
);

create index macro_observations_asof_idx
    on pit.macro_observations(series_code, observation_date, available_at desc);

-- ---------------------------------------------------------------------------
-- FUNDAMENTALS: standardized metrics and explicit adjustments
-- ---------------------------------------------------------------------------
create table fundamentals.metric_definitions (
    metric_code text primary key,
    name_cn text,
    name_en text not null,
    statement_type text,
    default_unit text,
    description text,
    created_at timestamptz not null default now()
);

create table fundamentals.normalized_facts (
    normalized_fact_id bigint generated always as identity primary key,
    issuer_id uuid not null references master.issuers(issuer_id),
    metric_code text not null references fundamentals.metric_definitions(metric_code),
    period_start date,
    period_end date not null,
    value_numeric numeric,
    value_text text,
    unit text,
    currency text,
    normalization_version text not null,
    available_at timestamptz not null,
    created_at timestamptz not null default now(),
    record_hash text,
    metadata jsonb not null default '{}'::jsonb,
    check (period_start is null or period_start <= period_end)
);

create index normalized_facts_asof_idx
    on fundamentals.normalized_facts(issuer_id, metric_code, period_end, available_at desc);
create unique index normalized_facts_record_hash_uq
    on fundamentals.normalized_facts(record_hash) where record_hash is not null;

create table fundamentals.fact_lineage (
    normalized_fact_id bigint not null references fundamentals.normalized_facts(normalized_fact_id) on delete cascade,
    source_fact_id bigint not null references pit.financial_facts(fact_id),
    lineage_role text not null default 'input',
    primary key (normalized_fact_id, source_fact_id)
);

create table fundamentals.adjustments (
    adjustment_id uuid primary key default gen_random_uuid(),
    issuer_id uuid not null references master.issuers(issuer_id),
    metric_code text not null,
    period_end date not null,
    as_of_at timestamptz not null,
    adjustment_value numeric,
    adjustment_text text,
    reason text not null,
    source_document_id uuid references raw.documents(document_id),
    adjustment_version text not null,
    status text not null default 'approved'
        check (status in ('draft', 'approved', 'rejected', 'superseded')),
    created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- AUDIT: immutable manifests, lineage and data-quality exceptions
-- ---------------------------------------------------------------------------
create table audit.data_snapshots (
    snapshot_id uuid primary key default gen_random_uuid(),
    as_of_at timestamptz not null,
    cutoff_policy_version text not null,
    manifest jsonb not null,
    snapshot_hash text not null unique,
    created_at timestamptz not null default now()
);

create table audit.data_quality_issues (
    issue_id uuid primary key default gen_random_uuid(),
    detected_at timestamptz not null default now(),
    severity text not null check (severity in ('info', 'warning', 'error', 'critical')),
    domain text not null,
    table_name text,
    record_key text,
    rule_code text not null,
    description text not null,
    status text not null default 'open'
        check (status in ('open', 'acknowledged', 'resolved', 'wont_fix')),
    details jsonb not null default '{}'::jsonb,
    resolved_at timestamptz
);

-- ---------------------------------------------------------------------------
-- MODEL: versioned valuation and reverse-valuation runs
-- ---------------------------------------------------------------------------
create table model.model_versions (
    model_version_id uuid primary key default gen_random_uuid(),
    model_name text not null,
    semantic_version text not null,
    model_family text not null,
    status text not null default 'development'
        check (status in ('development', 'validated', 'frozen', 'retired')),
    git_commit_sha text,
    config_hash text,
    effective_from timestamptz,
    notes text,
    created_at timestamptz not null default now(),
    unique (model_name, semantic_version)
);

create table model.issuer_model_assignments (
    assignment_id uuid primary key default gen_random_uuid(),
    issuer_id uuid not null references master.issuers(issuer_id),
    model_family text not null,
    valid_from date not null,
    valid_to date,
    rationale text,
    created_at timestamptz not null default now(),
    check (valid_to is null or valid_to >= valid_from)
);

create index issuer_model_assignments_asof_idx
    on model.issuer_model_assignments(issuer_id, valid_from, valid_to);

create table model.valuation_runs (
    run_id uuid primary key default gen_random_uuid(),
    issuer_id uuid not null references master.issuers(issuer_id),
    security_id uuid references master.securities(security_id),
    as_of_at timestamptz not null,
    snapshot_id uuid not null references audit.data_snapshots(snapshot_id),
    model_version_id uuid not null references model.model_versions(model_version_id),
    scenario_set_version text not null,
    status text not null default 'queued'
        check (status in ('queued', 'running', 'succeeded', 'failed', 'invalidated')),
    started_at timestamptz,
    completed_at timestamptz,
    input_hash text,
    output_hash text,
    error_text text,
    created_at timestamptz not null default now(),
    check (completed_at is null or started_at is null or completed_at >= started_at)
);

create index valuation_runs_issuer_asof_idx on model.valuation_runs(issuer_id, as_of_at desc);

-- Restored canonical foundation tail.
-- Bootstrap compatibility tail for the originally truncated foundation file.
-- The live Supabase project already has these objects; IF NOT EXISTS keeps this
-- migration safe while allowing a fresh PostgreSQL/Supabase database to build.

create table if not exists model.run_assumptions (
    assumption_id bigint generated always as identity primary key,
    run_id uuid not null references model.valuation_runs(run_id) on delete cascade,
    scenario text not null,
    assumption_key text not null,
    value_numeric numeric,
    value_text text,
    value_json jsonb,
    unit text,
    source_kind text not null default 'model',
    provenance jsonb not null default '{}'::jsonb,
    constraint run_assumptions_one_value_check
        check (num_nonnulls(value_numeric, value_text, value_json) = 1),
    constraint run_assumptions_run_scenario_key_uq
        unique (run_id, scenario, assumption_key)
);

create table if not exists model.valuation_outputs (
    output_id bigint generated always as identity primary key,
    run_id uuid not null references model.valuation_runs(run_id) on delete cascade,
    scenario text not null,
    output_key text not null,
    value_numeric numeric,
    value_text text,
    unit text,
    metadata jsonb not null default '{}'::jsonb,
    constraint valuation_outputs_one_value_check
        check (num_nonnulls(value_numeric, value_text) = 1),
    constraint valuation_outputs_run_scenario_key_uq
        unique (run_id, scenario, output_key)
);

create table if not exists model.reverse_dcf_results (
    reverse_result_id uuid primary key default gen_random_uuid(),
    run_id uuid not null references model.valuation_runs(run_id) on delete cascade,
    target_price numeric not null,
    solved_variable text not null,
    solution_value numeric,
    lower_bound numeric,
    upper_bound numeric,
    residual numeric,
    iterations integer,
    converged boolean not null default false,
    diagnostics jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    constraint reverse_dcf_results_run_target_variable_uq
        unique (run_id, target_price, solved_variable),
    constraint reverse_dcf_results_bounds_check
        check (lower_bound is null or upper_bound is null or lower_bound <= upper_bound)
);

create table if not exists backtest.universes (
    universe_id uuid primary key default gen_random_uuid(),
    universe_code text not null unique,
    name text not null,
    description text,
    construction_policy_version text not null,
    benchmark_security_id uuid references master.securities(security_id),
    created_at timestamptz not null default now()
);

create table if not exists backtest.universe_memberships (
    membership_id bigint generated always as identity primary key,
    universe_id uuid not null references backtest.universes(universe_id) on delete cascade,
    security_id uuid not null references master.securities(security_id),
    valid_from date not null,
    valid_to date,
    eligibility_reason jsonb not null default '{}'::jsonb,
    source_document_id uuid references raw.documents(document_id),
    constraint universe_memberships_validity_check
        check (valid_to is null or valid_to >= valid_from),
    constraint universe_memberships_universe_security_from_uq
        unique (universe_id, security_id, valid_from)
);

create table if not exists backtest.backtest_runs (
    backtest_run_id uuid primary key default gen_random_uuid(),
    universe_id uuid not null references backtest.universes(universe_id),
    model_version_id uuid not null references model.model_versions(model_version_id),
    start_date date not null,
    end_date date not null,
    holding_horizon_months integer,
    configuration jsonb not null,
    git_commit_sha text,
    status text not null default 'queued'
        check (status in ('queued','running','succeeded','failed')),
    started_at timestamptz,
    completed_at timestamptz,
    result_hash text,
    created_at timestamptz not null default now(),
    constraint backtest_runs_date_check check (end_date >= start_date),
    constraint backtest_runs_horizon_check
        check (holding_horizon_months is null or holding_horizon_months > 0)
);

create table if not exists backtest.decision_events (
    decision_id uuid primary key default gen_random_uuid(),
    backtest_run_id uuid not null
        references backtest.backtest_runs(backtest_run_id) on delete cascade,
    decision_at timestamptz not null,
    issuer_id uuid not null references master.issuers(issuer_id),
    security_id uuid not null references master.securities(security_id),
    valuation_run_id uuid references model.valuation_runs(run_id),
    signal text,
    rank_value numeric,
    target_weight numeric,
    decision_payload jsonb not null default '{}'::jsonb,
    frozen_at timestamptz not null default now(),
    constraint decision_events_run_date_security_uq
        unique (backtest_run_id, decision_at, security_id)
);

create table if not exists backtest.transactions (
    transaction_id bigint generated always as identity primary key,
    backtest_run_id uuid not null
        references backtest.backtest_runs(backtest_run_id) on delete cascade,
    decision_id uuid references backtest.decision_events(decision_id),
    security_id uuid not null references master.securities(security_id),
    trade_date date not null,
    side text not null,
    quantity numeric not null,
    price numeric not null,
    fees numeric not null default 0,
    slippage numeric not null default 0,
    currency text not null,
    constraint transactions_quantity_check check (quantity >= 0),
    constraint transactions_price_check check (price >= 0),
    constraint transactions_costs_check check (fees >= 0 and slippage >= 0)
);

create table if not exists backtest.position_snapshots (
    backtest_run_id uuid not null
        references backtest.backtest_runs(backtest_run_id) on delete cascade,
    trade_date date not null,
    security_id uuid not null references master.securities(security_id),
    quantity numeric not null,
    market_value numeric not null,
    weight numeric,
    currency text not null,
    primary key (backtest_run_id, trade_date, security_id)
);

create table if not exists backtest.daily_performance (
    backtest_run_id uuid not null
        references backtest.backtest_runs(backtest_run_id) on delete cascade,
    trade_date date not null,
    nav numeric not null,
    daily_return numeric,
    benchmark_return numeric,
    cash_value numeric,
    gross_exposure numeric,
    drawdown numeric,
    primary key (backtest_run_id, trade_date),
    constraint daily_performance_nav_check check (nav >= 0),
    constraint daily_performance_drawdown_check
        check (drawdown is null or drawdown <= 0)
);

create table if not exists audit.run_lineage (
    lineage_id bigint generated always as identity primary key,
    run_type text not null,
    run_id uuid not null,
    input_type text not null,
    input_id text,
    input_hash text,
    metadata jsonb not null default '{}'::jsonb,
    recorded_at timestamptz not null default now()
);

-- Research schemas are internal. Grants remain opt-in, even when the roles exist.
revoke all privileges on schema master, raw, pit, fundamentals, model, backtest, audit
    from anon, authenticated;
revoke all privileges on all tables in schema master, raw, pit, fundamentals, model, backtest, audit
    from anon, authenticated;
revoke all privileges on all sequences in schema master, raw, pit, fundamentals, model, backtest, audit
    from anon, authenticated;
revoke all privileges on all functions in schema master, raw, pit, fundamentals, model, backtest, audit
    from anon, authenticated;

alter default privileges for role postgres in schema master
    revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema raw
    revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema pit
    revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema fundamentals
    revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema model
    revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema backtest
    revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema audit
    revoke all on tables from anon, authenticated;

commit;
