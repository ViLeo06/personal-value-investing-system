begin;

create table if not exists backtest.run_metrics (
    backtest_run_id uuid not null references backtest.backtest_runs(backtest_run_id) on delete cascade,
    metric_code text not null,
    value_numeric numeric,
    value_text text,
    unit text,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    primary key (backtest_run_id,metric_code),
    constraint run_metrics_one_value_chk check (num_nonnulls(value_numeric,value_text)=1)
);

create index if not exists run_metrics_code_idx
    on backtest.run_metrics(metric_code,backtest_run_id);

revoke all on table backtest.run_metrics from anon,authenticated;

commit;
