begin;

-- This seed is intentionally a no-op until an unadjusted 2021-03-31 bar exists.
with s as (
  select snapshot_id from audit.data_snapshots
  where snapshot_hash='9950df576f62d3a87aac8b7ee276a173'
  order by created_at desc limit 1
), bar as (
  select mb.* from pit.market_bars mb
  join master.securities sec using(security_id)
  join raw.data_sources src on src.source_id=mb.source_id
  where sec.security_code='600519.SH' and mb.trade_date=date '2021-03-31'
    and mb.available_at<=timestamptz '2021-04-01 00:00:00+08'
  order by case when src.source_code='EASTMONEY_PUBLIC_API' then 0 else 1 end,
           mb.ingested_at desc limit 1
)
insert into audit.snapshot_items
    (snapshot_id,input_type,input_id,input_key,input_hash,source_available_at,metadata)
select s.snapshot_id,'pit.market_bars',bar.bar_id::text,
       '600519.SH|2021-03-31|unadjusted|EASTMONEY_PUBLIC_API',bar.record_hash,
       bar.available_at,jsonb_build_object('role','market_expectation_target',
                                           'price_field','close_price','trade_date',bar.trade_date,
                                           'adjustment','unadjusted')
from s cross join bar
on conflict (snapshot_id,input_type,input_id) do update
set input_key=excluded.input_key,input_hash=excluded.input_hash,
    source_available_at=excluded.source_available_at,metadata=excluded.metadata;

with digest as (
  select snapshot_id,count(*)::int as item_count,
         md5(string_agg(concat_ws('|',input_type,input_key,coalesce(input_hash,'')),
                        '||' order by input_type,input_key)) as membership_hash
  from audit.snapshot_items group by snapshot_id
)
update audit.data_snapshots ds
set manifest=ds.manifest || jsonb_build_object(
      'scope','prototype_phase_a_inputs','snapshot_item_count',d.item_count,
      'membership_hash',d.membership_hash,'membership_hash_version','stable_input_key_v1',
      'membership_materialized',true,
      'market_price_policy','last completed unadjusted close available at signal cutoff',
      'market_price_trade_date','2021-03-31')
from digest d
where ds.snapshot_id=d.snapshot_id
  and ds.snapshot_hash='9950df576f62d3a87aac8b7ee276a173';

with context as (
  select vr.run_id,mb.close_price,mb.bar_id,mb.record_hash,mb.trade_date,mb.available_at
  from model.valuation_runs vr
  join master.issuers i on i.issuer_id=vr.issuer_id
  join master.securities sec on sec.security_id=vr.security_id
  join pit.market_bars mb on mb.security_id=sec.security_id and mb.trade_date=date '2021-03-31'
  where i.issuer_code='KWEICHOW_MOUTAI'
    and vr.scenario_set_version='moutai_gate0_scenarios_v1'
  order by vr.created_at desc,mb.ingested_at desc limit 1
)
delete from model.run_assumptions ra using context c
where ra.run_id=c.run_id and ra.scenario='market_expectations'
  and ra.assumption_key='target_market_price';

with context as (
  select vr.run_id,mb.close_price,mb.bar_id,mb.record_hash,mb.trade_date,mb.available_at
  from model.valuation_runs vr
  join master.issuers i on i.issuer_id=vr.issuer_id
  join master.securities sec on sec.security_id=vr.security_id
  join pit.market_bars mb on mb.security_id=sec.security_id and mb.trade_date=date '2021-03-31'
  where i.issuer_code='KWEICHOW_MOUTAI'
    and vr.scenario_set_version='moutai_gate0_scenarios_v1'
  order by vr.created_at desc,mb.ingested_at desc limit 1
)
insert into model.run_assumptions
    (run_id,scenario,assumption_key,value_numeric,unit,source_kind,provenance)
select run_id,'market_expectations','target_market_price',close_price,'CNY/share','market_bar',
       jsonb_build_object('bar_id',bar_id,'record_hash',record_hash,'trade_date',trade_date,
                          'available_at',available_at,'price_field','close_price',
                          'adjustment','unadjusted','price_role','last_completed_close_before_signal')
from context;

with context as (
  select vr.run_id,mb.close_price,mb.bar_id,mb.record_hash,
         max(n.value_numeric) filter(where n.metric_code='owner_earnings_proxy') as owner_earnings,
         max(n.value_numeric) filter(where n.metric_code='shares_outstanding_proxy') as shares
  from model.valuation_runs vr
  join master.issuers i on i.issuer_id=vr.issuer_id
  join master.securities sec on sec.security_id=vr.security_id
  join pit.market_bars mb on mb.security_id=sec.security_id and mb.trade_date=date '2021-03-31'
  join fundamentals.normalized_facts n on n.issuer_id=vr.issuer_id
       and n.period_end=date '2020-12-31' and n.normalization_version='gate0_v1'
       and n.metric_code in ('owner_earnings_proxy','shares_outstanding_proxy')
  where i.issuer_code='KWEICHOW_MOUTAI'
    and vr.scenario_set_version='moutai_gate0_scenarios_v1'
  group by vr.run_id,mb.close_price,mb.bar_id,mb.record_hash,vr.created_at,mb.ingested_at
  order by vr.created_at desc,mb.ingested_at desc limit 1
)
delete from model.reverse_dcf_results r using context c
where r.run_id=c.run_id and r.solved_variable='stage1_growth';

with context as (
  select vr.run_id,mb.close_price,mb.bar_id,mb.record_hash,
         max(n.value_numeric) filter(where n.metric_code='owner_earnings_proxy') as owner_earnings,
         max(n.value_numeric) filter(where n.metric_code='shares_outstanding_proxy') as shares
  from model.valuation_runs vr
  join master.issuers i on i.issuer_id=vr.issuer_id
  join master.securities sec on sec.security_id=vr.security_id
  join pit.market_bars mb on mb.security_id=sec.security_id and mb.trade_date=date '2021-03-31'
  join fundamentals.normalized_facts n on n.issuer_id=vr.issuer_id
       and n.period_end=date '2020-12-31' and n.normalization_version='gate0_v1'
       and n.metric_code in ('owner_earnings_proxy','shares_outstanding_proxy')
  where i.issuer_code='KWEICHOW_MOUTAI'
    and vr.scenario_set_version='moutai_gate0_scenarios_v1'
  group by vr.run_id,mb.close_price,mb.bar_id,mb.record_hash,vr.created_at,mb.ingested_at
  order by vr.created_at desc,mb.ingested_at desc limit 1
), solution as (
  select c.*,s.* from context c
  cross join lateral model.solve_owner_earnings_stage1_growth(
    c.close_price,c.owner_earnings,c.shares,0.09::numeric,0.03::numeric,
    -0.20::numeric,0.40::numeric,0.00000001::numeric,200,10,5,0.15::numeric) s
)
insert into model.reverse_dcf_results
    (run_id,target_price,solved_variable,solution_value,lower_bound,upper_bound,
     residual,iterations,converged,diagnostics)
select run_id,close_price,'stage1_growth',solution_value,lower_bound,upper_bound,
       residual,iterations,converged,
       jsonb_build_object('discount_rate',0.09,'terminal_growth',0.03,
                          'forecast_horizon_years',10,'stage1_years',5,
                          'market_bar_id',bar_id,'market_bar_hash',record_hash,
                          'shared_forward_function','model.owner_earnings_dcf_components',
                          'solver_function','model.solve_owner_earnings_stage1_growth')
from solution;

commit;
