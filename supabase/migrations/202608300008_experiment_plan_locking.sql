begin;

create table audit.experiment_plans (
    plan_id uuid primary key default gen_random_uuid(),
    plan_code text not null unique,
    name text not null,
    objective text not null,
    selection_policy jsonb not null,
    outcome_policy jsonb not null,
    plan_hash text not null unique,
    status text not null default 'draft'
        check (status in ('draft','locked','running','completed','superseded')),
    created_at timestamptz not null default now(),
    locked_at timestamptz,
    completed_at timestamptz,
    supersedes_plan_id uuid references audit.experiment_plans(plan_id),
    metadata jsonb not null default '{}'::jsonb,
    constraint experiment_plans_lock_state_check
        check (
            (status='draft' and locked_at is null)
            or (status<>'draft' and locked_at is not null)
        )
);

create table audit.experiment_plan_decisions (
    plan_decision_id uuid primary key default gen_random_uuid(),
    plan_id uuid not null
        references audit.experiment_plans(plan_id) on delete cascade,
    issuer_id uuid not null references master.issuers(issuer_id),
    security_id uuid not null references master.securities(security_id),
    decision_at timestamptz not null,
    cohort_code text not null,
    model_family text not null,
    horizon_months integer not null check (horizon_months > 0),
    expected_maturity_date date not null,
    decision_order integer not null check (decision_order > 0),
    metadata jsonb not null default '{}'::jsonb,
    unique (plan_id, security_id, decision_at),
    unique (plan_id, decision_order)
);

create table audit.experiment_plan_events (
    event_id bigint generated always as identity primary key,
    plan_id uuid not null
        references audit.experiment_plans(plan_id) on delete cascade,
    event_at timestamptz not null default now(),
    event_type text not null check (event_type in (
        'created','locked','run_started','run_completed','superseded','note'
    )),
    event_payload jsonb not null default '{}'::jsonb
);

create or replace function audit.protect_locked_experiment_plan()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, audit
as $$
begin
    if tg_op = 'DELETE' and old.status <> 'draft' then
        raise exception 'locked experiment plans cannot be deleted';
    end if;
    if tg_op = 'UPDATE' and old.status <> 'draft' then
        if new.plan_code is distinct from old.plan_code
           or new.objective is distinct from old.objective
           or new.selection_policy is distinct from old.selection_policy
           or new.outcome_policy is distinct from old.outcome_policy
           or new.plan_hash is distinct from old.plan_hash
           or new.locked_at is distinct from old.locked_at then
            raise exception 'locked experiment plan design cannot be modified';
        end if;
    end if;
    return coalesce(new, old);
end;
$$;

create or replace function audit.protect_locked_experiment_decisions()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, audit
as $$
declare
    plan_status text;
begin
    select status into plan_status
    from audit.experiment_plans
    where plan_id = coalesce(new.plan_id, old.plan_id);
    if plan_status <> 'draft' then
        raise exception 'decision rows of a locked experiment plan are immutable';
    end if;
    return coalesce(new, old);
end;
$$;

create trigger protect_locked_experiment_plan_trigger
before update or delete on audit.experiment_plans
for each row execute function audit.protect_locked_experiment_plan();

create trigger protect_locked_experiment_decisions_trigger
before insert or update or delete on audit.experiment_plan_decisions
for each row execute function audit.protect_locked_experiment_decisions();

create index experiment_plan_decisions_plan_date_idx
    on audit.experiment_plan_decisions(plan_id, decision_at);
create index experiment_plan_decisions_issuer_date_idx
    on audit.experiment_plan_decisions(issuer_id, decision_at);
create index experiment_plan_events_plan_event_idx
    on audit.experiment_plan_events(plan_id, event_at);

revoke all privileges on audit.experiment_plans,
    audit.experiment_plan_decisions,
    audit.experiment_plan_events from anon, authenticated;
revoke all privileges on sequence audit.experiment_plan_events_event_id_seq
    from anon, authenticated;
revoke all on function audit.protect_locked_experiment_plan()
    from public, anon, authenticated;
revoke all on function audit.protect_locked_experiment_decisions()
    from public, anon, authenticated;

commit;
