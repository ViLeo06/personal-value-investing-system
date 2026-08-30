begin;

with design as (
    select
        'GATE0_NATIVE_4X3_V1'::text as plan_code,
        'Gate 0 native valuation replay: four companies × three fixed dates'::text as name,
        'Validate native PIT valuation, decision, outcome and attribution across four model families before expanding the universe.'::text as objective,
        jsonb_build_object(
            'companies',jsonb_build_array('KWEICHOW_MOUTAI','TENCENT','BYD','CMB'),
            'decision_dates',jsonb_build_array('2016-08-30','2019-08-30','2021-08-30'),
            'date_selection','same calendar date across issuers; dates fixed before completing native outcomes',
            'security_selection',jsonb_build_object(
                'KWEICHOW_MOUTAI','600519.SH',
                'TENCENT','0700.HK',
                'BYD','002594.SZ',
                'CMB','600036.SH'
            ),
            'exchange_cutoff','official local market close',
            'horizon_months',60,
            'survivorship_bias_note','named Gate-0 validation issuers; not a strategy universe sample',
            'non_overlapping_reporting_required',true
        ) as selection_policy,
        jsonb_build_object(
            'primary_horizon_months',60,
            'outcome_price','last eligible trading close on or before calendar maturity date',
            'corporate_actions','official event ledger with explicit reinvestment rule',
            'benchmark','exact-window total-return benchmark in the security reporting currency',
            'pending_samples','never mixed with mature five-year samples',
            'phase_separation','Phase A decision frozen before Phase B outcome attachment'
        ) as outcome_policy
), hashed as (
    select *,encode(
        digest(
            convert_to(
                jsonb_build_object(
                    'plan_code',plan_code,
                    'objective',objective,
                    'selection_policy',selection_policy,
                    'outcome_policy',outcome_policy
                )::text,
                'UTF8'
            ),
            'sha256'
        ),
        'hex'
    ) as plan_hash
    from design
)
insert into audit.experiment_plans (
    plan_code,name,objective,selection_policy,outcome_policy,plan_hash,status,metadata
)
select plan_code,name,objective,selection_policy,outcome_policy,plan_hash,'draft',
       '{"created_by":"V1.2 architecture implementation","outcomes_consulted_for_date_selection":false}'::jsonb
from hashed
on conflict (plan_code) do nothing;

with plan as (
    select plan_id from audit.experiment_plans
    where plan_code='GATE0_NATIVE_4X3_V1'
), rows(
    issuer_code,security_code,decision_at,cohort_code,model_family,
    expected_maturity_date,decision_order
) as (
    values
    ('KWEICHOW_MOUTAI','600519.SH','2016-08-30 15:00:00+08'::timestamptz,'GATE0_2016','owner_earnings_dcf','2021-08-30'::date,1),
    ('TENCENT','0700.HK','2016-08-30 16:00:00+08','GATE0_2016','fcff_sotp','2021-08-30',2),
    ('BYD','002594.SZ','2016-08-30 15:00:00+08','GATE0_2016','value_driver_fcff','2021-08-30',3),
    ('CMB','600036.SH','2016-08-30 15:00:00+08','GATE0_2016','residual_income','2021-08-30',4),
    ('KWEICHOW_MOUTAI','600519.SH','2019-08-30 15:00:00+08','GATE0_2019','owner_earnings_dcf','2024-08-30',5),
    ('TENCENT','0700.HK','2019-08-30 16:00:00+08','GATE0_2019','fcff_sotp','2024-08-30',6),
    ('BYD','002594.SZ','2019-08-30 15:00:00+08','GATE0_2019','value_driver_fcff','2024-08-30',7),
    ('CMB','600036.SH','2019-08-30 15:00:00+08','GATE0_2019','residual_income','2024-08-30',8),
    ('KWEICHOW_MOUTAI','600519.SH','2021-08-30 15:00:00+08','GATE0_2021','owner_earnings_dcf','2026-08-30',9),
    ('TENCENT','0700.HK','2021-08-30 16:00:00+08','GATE0_2021','fcff_sotp','2026-08-30',10),
    ('BYD','002594.SZ','2021-08-30 15:00:00+08','GATE0_2021','value_driver_fcff','2026-08-30',11),
    ('CMB','600036.SH','2021-08-30 15:00:00+08','GATE0_2021','residual_income','2026-08-30',12)
)
insert into audit.experiment_plan_decisions (
    plan_id,issuer_id,security_id,decision_at,cohort_code,model_family,
    horizon_months,expected_maturity_date,decision_order,metadata
)
select plan.plan_id,i.issuer_id,s.security_id,rows.decision_at,rows.cohort_code,
       rows.model_family,60,rows.expected_maturity_date,rows.decision_order,
       jsonb_build_object(
           'issuer_code',rows.issuer_code,
           'security_code',rows.security_code,
           'phase_a_status',case
               when rows.issuer_code='KWEICHOW_MOUTAI'
                and rows.decision_at='2021-08-30 15:00:00+08'::timestamptz
               then 'reproducible_provisional'
               else 'planned'
           end
       )
from plan cross join rows
join master.issuers i on i.issuer_code=rows.issuer_code
join master.securities s on s.issuer_id=i.issuer_id and s.security_code=rows.security_code
where not exists (
    select 1 from audit.experiment_plan_decisions epd
    where epd.plan_id=plan.plan_id and epd.security_id=s.security_id
      and epd.decision_at=rows.decision_at
);

insert into audit.experiment_plan_events (plan_id,event_type,event_payload)
select plan_id,'created','{"decision_count":12}'::jsonb
from audit.experiment_plans p
where p.plan_code='GATE0_NATIVE_4X3_V1'
  and not exists (
      select 1 from audit.experiment_plan_events e
      where e.plan_id=p.plan_id and e.event_type='created'
  );

update audit.experiment_plans
set status='locked',locked_at='2026-08-30 19:00:00+08'
where plan_code='GATE0_NATIVE_4X3_V1' and status='draft';

insert into audit.experiment_plan_events (plan_id,event_at,event_type,event_payload)
select plan_id,locked_at,'locked',jsonb_build_object(
           'plan_hash',plan_hash,
           'decision_count',(select count(*) from audit.experiment_plan_decisions d where d.plan_id=p.plan_id)
       )
from audit.experiment_plans p
where p.plan_code='GATE0_NATIVE_4X3_V1'
  and not exists (
      select 1 from audit.experiment_plan_events e
      where e.plan_id=p.plan_id and e.event_type='locked'
  );

commit;
