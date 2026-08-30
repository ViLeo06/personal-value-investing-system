begin;

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
    if tg_op = 'DELETE' then
        return old;
    end if;
    return new;
end;
$$;

create or replace function audit.protect_locked_experiment_decisions()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, audit
as $$
declare
    target_plan_id uuid;
    plan_status text;
begin
    if tg_op = 'DELETE' then
        target_plan_id := old.plan_id;
    else
        target_plan_id := new.plan_id;
    end if;

    select status into plan_status
    from audit.experiment_plans
    where plan_id = target_plan_id;

    if plan_status is null then
        raise exception 'experiment plan does not exist: %', target_plan_id;
    end if;
    if plan_status <> 'draft' then
        raise exception 'decision rows of a locked experiment plan are immutable';
    end if;

    if tg_op = 'DELETE' then
        return old;
    end if;
    return new;
end;
$$;

revoke all on function audit.protect_locked_experiment_plan()
    from public, anon, authenticated;
revoke all on function audit.protect_locked_experiment_decisions()
    from public, anon, authenticated;

commit;
