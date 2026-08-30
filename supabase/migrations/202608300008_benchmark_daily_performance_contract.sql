begin;

create table if not exists backtest.benchmark_daily_performance (
    backtest_run_id uuid not null references backtest.backtest_runs(backtest_run_id) on delete cascade,
    benchmark_security_id uuid not null references master.securities(security_id),
    trade_date date not null,
    nav numeric not null,
    daily_return numeric,
    cash_value numeric not null default 0,
    gross_exposure numeric not null default 0,
    drawdown numeric,
    metadata jsonb not null default '{}'::jsonb,
    primary key(backtest_run_id,benchmark_security_id,trade_date)
);

create index if not exists benchmark_daily_security_date_idx
  on backtest.benchmark_daily_performance(benchmark_security_id,trade_date);

revoke all on table backtest.benchmark_daily_performance from anon,authenticated;

commit;
