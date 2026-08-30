begin;

do $$
declare
    target_plan_id uuid;
    decision_count integer;
    update_blocked boolean := false;
    insert_blocked boolean := false;
begin
    select plan_id into target_plan_id
    from audit.experiment_plans
    where plan_code='GATE0_NATIVE_4X3_V1';

    if target_plan_id is null then
        raise exception 'Gate 0 experiment plan is missing';
    end if;

    select count(*) into decision_count
    from audit.experiment_plan_decisions
    where plan_id=target_plan_id;
    if decision_count <> 12 then
        raise exception 'expected 12 locked decision rows, got %', decision_count;
    end if;

    begin
        update audit.experiment_plans
        set selection_policy=selection_policy || '{"tampered":true}'::jsonb
        where plan_id=target_plan_id;
    exception when others then
        update_blocked := true;
    end;
    if not update_blocked then
        raise exception 'locked plan design update was not blocked';
    end if;

    begin
        insert into audit.experiment_plan_decisions (
            plan_id,issuer_id,security_id,decision_at,cohort_code,model_family,
            horizon_months,expected_maturity_date,decision_order
        )
        select target_plan_id,i.issuer_id,s.security_id,
               '2018-08-30 15:00:00+08','TAMPER','owner_earnings_dcf',
               60,'2023-08-30',99
        from master.issuers i
        join master.securities s on s.issuer_id=i.issuer_id
        where i.issuer_code='KWEICHOW_MOUTAI' and s.security_code='600519.SH';
    exception when others then
        insert_blocked := true;
    end;
    if not insert_blocked then
        raise exception 'locked plan decision insert was not blocked';
    end if;
end $$;

rollback;
