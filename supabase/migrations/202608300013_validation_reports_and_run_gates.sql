begin;

alter table model.valuation_runs
    add column if not exists validation_status text not null default 'not_run',
    add column if not exists allocation_eligibility text not null default 'blocked';

alter table model.valuation_runs
    drop constraint if exists valuation_runs_validation_status_check,
    add constraint valuation_runs_validation_status_check
        check (validation_status in (
            'not_run','passed','passed_with_warnings','failed'
        )),
    drop constraint if exists valuation_runs_allocation_eligibility_check,
    add constraint valuation_runs_allocation_eligibility_check
        check (allocation_eligibility in ('blocked','research_only','eligible'));

alter table backtest.backtest_runs
    add column if not exists validation_status text not null default 'not_run';

alter table backtest.backtest_runs
    drop constraint if exists backtest_runs_validation_status_check,
    add constraint backtest_runs_validation_status_check
        check (validation_status in (
            'not_run','passed','passed_with_warnings','failed'
        ));

create table audit.validation_runs (
    validation_run_id uuid primary key default gen_random_uuid(),
    target_type text not null check (target_type in (
        'data_snapshot','valuation_run','decision_event','backtest_run','dataset_export'
    )),
    target_id text not null,
    ruleset_version text not null,
    status text not null default 'running'
        check (status in ('running','passed','passed_with_warnings','failed')),
    report_hash text,
    started_at timestamptz not null default now(),
    completed_at timestamptz,
    metadata jsonb not null default '{}'::jsonb,
    constraint validation_runs_completion_check
        check (
            (status='running' and completed_at is null)
            or (status<>'running' and completed_at is not null)
        ),
    unique (target_type,target_id,ruleset_version)
);

create table audit.validation_results (
    validation_result_id bigint generated always as identity primary key,
    validation_run_id uuid not null
        references audit.validation_runs(validation_run_id) on delete cascade,
    rule_code text not null,
    severity text not null check (severity in ('info','warning','error','critical')),
    passed boolean not null,
    message text not null,
    details jsonb not null default '{}'::jsonb,
    evaluated_at timestamptz not null default now(),
    unique (validation_run_id,rule_code)
);

create index validation_runs_target_idx
    on audit.validation_runs(target_type,target_id,status);
create index validation_results_failures_idx
    on audit.validation_results(validation_run_id,severity)
    where passed=false;

revoke all privileges on audit.validation_runs,
    audit.validation_results from anon, authenticated;
revoke all privileges on sequence audit.validation_results_validation_result_id_seq
    from anon, authenticated;

commit;
