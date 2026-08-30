begin;

create table backtest.decision_outcomes (
    outcome_id uuid primary key default gen_random_uuid(),
    decision_id uuid not null unique
        references backtest.decision_events(decision_id) on delete cascade,
    outcome_at timestamptz not null,
    horizon_years numeric not null check (horizon_years > 0),
    start_price numeric not null check (start_price > 0),
    end_price numeric not null check (end_price >= 0),
    final_share_multiplier numeric not null check (final_share_multiplier > 0),
    terminal_value numeric not null check (terminal_value >= 0),
    total_return numeric not null,
    annualized_return numeric not null,
    benchmark_annualized_return numeric,
    excess_return numeric,
    source_quality text not null
        check (source_quality in ('official', 'reconciled', 'provisional', 'legacy_proxy')),
    outcome_payload jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index decision_outcomes_outcome_at_idx
    on backtest.decision_outcomes(outcome_at);

create table backtest.attribution_results (
    attribution_id bigint generated always as identity primary key,
    outcome_id uuid not null
        references backtest.decision_outcomes(outcome_id) on delete cascade,
    attribution_key text not null,
    value_numeric numeric,
    value_text text,
    unit text,
    methodology_version text not null,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    unique (outcome_id, attribution_key, methodology_version)
);

create index attribution_results_outcome_idx
    on backtest.attribution_results(outcome_id);

revoke all privileges on backtest.decision_outcomes,
    backtest.attribution_results from anon, authenticated;
revoke all privileges on sequence backtest.attribution_results_attribution_id_seq
    from anon, authenticated;

commit;
