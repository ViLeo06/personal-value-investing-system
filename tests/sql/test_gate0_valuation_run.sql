-- These queries must return zero rows in a valid Gate-0 prototype database.

-- Scenario economics must satisfy terminal-value constraints.
select vr.run_id,ra.scenario,
       max(ra.value_numeric) filter(where ra.assumption_key='discount_rate') as discount_rate,
       max(ra.value_numeric) filter(where ra.assumption_key='terminal_growth') as terminal_growth
from model.valuation_runs vr
join master.issuers i on i.issuer_id=vr.issuer_id
join model.run_assumptions ra on ra.run_id=vr.run_id
where i.issuer_code='KWEICHOW_MOUTAI'
  and vr.scenario_set_version='moutai_gate0_scenarios_v1'
  and ra.scenario<>'all'
group by vr.run_id,ra.scenario
having max(ra.value_numeric) filter(where ra.assumption_key='discount_rate')
       <= max(ra.value_numeric) filter(where ra.assumption_key='terminal_growth');

-- Terminal-value share must remain a proper ratio.
select vo.*
from model.valuation_outputs vo
join model.valuation_runs vr using(run_id)
join master.issuers i on i.issuer_id=vr.issuer_id
where i.issuer_code='KWEICHOW_MOUTAI'
  and vr.scenario_set_version='moutai_gate0_scenarios_v1'
  and vo.output_key='terminal_value_share'
  and (vo.value_numeric<=0 or vo.value_numeric>=1);

-- Economic ordering should be pessimistic < base < optimistic.
with values_by_scenario as (
  select vr.run_id,vo.scenario,vo.value_numeric
  from model.valuation_runs vr
  join master.issuers i on i.issuer_id=vr.issuer_id
  join model.valuation_outputs vo using(run_id)
  where i.issuer_code='KWEICHOW_MOUTAI'
    and vr.scenario_set_version='moutai_gate0_scenarios_v1'
    and vo.output_key='intrinsic_value_per_share'
), pivoted as (
  select run_id,
         max(value_numeric) filter(where scenario='pessimistic') as pessimistic,
         max(value_numeric) filter(where scenario='base') as base,
         max(value_numeric) filter(where scenario='optimistic') as optimistic
  from values_by_scenario group by run_id
)
select * from pivoted
where not (pessimistic < base and base < optimistic);

-- Reverse DCF must remain absent while the critical price quality issue is open.
select r.*
from model.reverse_dcf_results r
join model.valuation_runs vr on vr.run_id=r.run_id
join master.issuers i on i.issuer_id=vr.issuer_id
where i.issuer_code='KWEICHOW_MOUTAI'
  and exists (
    select 1 from audit.data_quality_issues d
    where d.rule_code='DECISION_PRICE_NOT_LOADED'
      and d.record_key='600519.SH|2021-04-01'
      and d.status='open'
  );
