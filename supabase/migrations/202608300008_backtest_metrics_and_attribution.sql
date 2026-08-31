begin;

create table if not exists backtest.performance_metrics (
    backtest_run_id uuid not null references backtest.backtest_runs(backtest_run_id),
    metric_code text not null,
    value_numeric numeric,
    value_text text,
    unit text,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    primary key (backtest_run_id,metric_code),
    check (value_numeric is not null or value_text is not null)
);

create table if not exists backtest.attribution_results (
    backtest_run_id uuid not null references backtest.backtest_runs(backtest_run_id),
    attribution_date date,
    dimension_type text not null,
    dimension_value text not null,
    effect_code text not null,
    effect_value numeric not null,
    unit text not null,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    primary key (
        backtest_run_id,attribution_date,dimension_type,dimension_value,effect_code
    )
);

create index if not exists performance_metrics_code_idx
    on backtest.performance_metrics(metric_code);
create index if not exists attribution_results_effect_idx
    on backtest.attribution_results(effect_code,dimension_type);

revoke all on backtest.performance_metrics from public,anon,authenticated;
revoke all on backtest.attribution_results from public,anon,authenticated;

commit;
