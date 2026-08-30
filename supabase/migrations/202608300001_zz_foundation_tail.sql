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
