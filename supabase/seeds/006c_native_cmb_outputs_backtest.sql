begin;

with run as (
    select run_id from model.valuation_runs
    where input_hash='58d83f6292e59197fc4effb2bc3f98cd28c80cc4af1cf7af67d20a1b254fc683'
    order by created_at limit 1
), rows(scenario,output_key,value_numeric,value_text,unit,metadata) as (
    values
    ('pessimistic','intrinsic_value_per_share',20.69829893421815,null,'CNY/share','{"source":"native_residual_income_engine"}'::jsonb),
    ('pessimistic','predicted_5y_irr',-0.07204966900081006,null,'ratio','{"source":"native_residual_income_engine"}'::jsonb),
    ('pessimistic','target_buy_price_15pct',18.436331628671038,null,'CNY/share','{"source":"native_residual_income_engine"}'::jsonb),
    ('pessimistic','year_five_value_per_share',26.656159349697,null,'CNY/share','{"source":"native_residual_income_engine"}'::jsonb),
    ('pessimistic','terminal_value_share',-0.19313762998216835,null,'ratio','{"source":"native_residual_income_engine"}'::jsonb),
    ('pessimistic','price_to_book_value',0.7781315388803816,null,'multiple','{"source":"native_residual_income_engine"}'::jsonb),
    ('base','intrinsic_value_per_share',36.135509092814395,null,'CNY/share','{"source":"native_residual_income_engine"}'::jsonb),
    ('base','predicted_5y_irr',0.03755026696155135,null,'ratio','{"source":"native_residual_income_engine"}'::jsonb),
    ('base','target_buy_price_15pct',30.067466242836502,null,'CNY/share','{"source":"native_residual_income_engine"}'::jsonb),
    ('base','year_five_value_per_share',49.134674410901596,null,'CNY/share','{"source":"native_residual_income_engine"}'::jsonb),
    ('base','terminal_value_share',0.08255194298756388,null,'ratio','{"source":"native_residual_income_engine"}'::jsonb),
    ('base','price_to_book_value',1.35847778544415,null,'multiple','{"source":"native_residual_income_engine"}'::jsonb),
    ('optimistic','intrinsic_value_per_share',57.67577668835412,null,'CNY/share','{"source":"native_residual_income_engine"}'::jsonb),
    ('optimistic','predicted_5y_irr',0.13596337615433746,null,'ratio','{"source":"native_residual_income_engine"}'::jsonb),
    ('optimistic','target_buy_price_15pct',45.71678269240916,null,'CNY/share','{"source":"native_residual_income_engine"}'::jsonb),
    ('optimistic','year_five_value_per_share',79.9412286706059,null,'CNY/share','{"source":"native_residual_income_engine"}'::jsonb),
    ('optimistic','terminal_value_share',0.25728622226108805,null,'ratio','{"source":"native_residual_income_engine"}'::jsonb),
    ('optimistic','price_to_book_value',2.1682622815170722,null,'multiple','{"source":"native_residual_income_engine"}'::jsonb),
    ('market_expectations','implied_uniform_roe',0.17671456246762313,null,'ratio','{"target_price":48.45,"forward_model":"residual_income"}'::jsonb),
    ('decision','signal',null,'avoid_at_price',null,'{"hurdle":0.15,"automatic_allocation_eligible":false}'::jsonb),
    ('decision','native_minus_legacy_base_value',-4.164490907185602,null,'CNY/share','{"legacy_base_value":40.30}'::jsonb),
    ('phase_b','realized_tsr_cagr',0.0062381161097595506,null,'ratio','{"source":"legacy_proxy_ledger"}'::jsonb),
    ('phase_b','base_forecast_error',-0.0313121508517918,null,'ratio','{"formula":"actual_cagr - native_base_irr"}'::jsonb)
)
insert into model.valuation_outputs (
    run_id,scenario,output_key,value_numeric,value_text,unit,metadata
)
select run.run_id,rows.scenario,rows.output_key,rows.value_numeric,
       rows.value_text,rows.unit,rows.metadata
from run cross join rows
on conflict (run_id,scenario,output_key) do update set
    value_numeric=excluded.value_numeric,value_text=excluded.value_text,
    unit=excluded.unit,metadata=excluded.metadata;

with run as (
    select run_id from model.valuation_runs
    where input_hash='58d83f6292e59197fc4effb2bc3f98cd28c80cc4af1cf7af67d20a1b254fc683'
    order by created_at limit 1
)
insert into model.reverse_dcf_results (
    run_id,target_price,solved_variable,solution_value,lower_bound,upper_bound,
    residual,iterations,converged,diagnostics
)
select run_id,48.45,'uniform_explicit_roe',0.17671456246762313,-0.2,
       0.5,2.3504753698944114e-11,40,true,
       '{"forward_model":"residual_income","fixed_scenario":"base","reported_annualized_roe":0.1806}'::jsonb
from run
where not exists (
    select 1 from model.reverse_dcf_results r
    where r.run_id=run.run_id and r.solved_variable='uniform_explicit_roe'
);

insert into backtest.universes (
    universe_code,name,description,construction_policy_version
) values (
    'GATE0_NATIVE_CMB_20210830','Gate 0 native CMB 2021-08-30 replay',
    'Single-security native PIT bank replay validating residual-income valuation, market-implied ROE, decision freeze and endpoint attribution.',
    'single_security_native_v1'
)
on conflict (universe_code) do update set name=excluded.name,
    description=excluded.description,
    construction_policy_version=excluded.construction_policy_version;

insert into backtest.universe_memberships (
    universe_id,security_id,valid_from,valid_to,eligibility_reason
)
select u.universe_id,s.security_id,'2002-04-09',null,
       '{"reason":"Gate 0 named validation security","selection_is_not_point_in_time_universe_sample":true}'::jsonb
from backtest.universes u
join master.securities s on s.security_code='600036.SH'
where u.universe_code='GATE0_NATIVE_CMB_20210830'
  and not exists (
      select 1 from backtest.universe_memberships um
      where um.universe_id=u.universe_id and um.security_id=s.security_id
        and um.valid_from='2002-04-09' and um.valid_to is null
  );

insert into backtest.backtest_runs (
    universe_id,model_version_id,start_date,end_date,holding_horizon_months,
    configuration,git_commit_sha,status,started_at,completed_at,result_hash,
    validation_status
)
select u.universe_id,mv.model_version_id,'2021-08-30','2026-08-28',60,
       '{"mode":"single_security_counterfactual_endpoint_replay","phase_a_frozen":true,"daily_performance_loaded":false,"corporate_action_source":"legacy_proxy_pending_official_replacement","investment_hurdle":0.15}'::jsonb,
       '12ca182d1c00a0c485c79eb9b483a8111aa213ee','succeeded',now(),now(),
       'e51a86c77ad178a8da40684e2d870348e109b0755b5e213b1096ddb03d777698',
       'passed_with_warnings'
from backtest.universes u
join model.model_versions mv
  on mv.model_name='cmb_residual_income_native'
 and mv.semantic_version='1.0.0'
where u.universe_code='GATE0_NATIVE_CMB_20210830'
  and not exists (
      select 1 from backtest.backtest_runs br
      where br.universe_id=u.universe_id
        and br.model_version_id=mv.model_version_id
        and br.start_date='2021-08-30'
        and br.result_hash='e51a86c77ad178a8da40684e2d870348e109b0755b5e213b1096ddb03d777698'
  );

with br as (
    select br.backtest_run_id
    from backtest.backtest_runs br
    join backtest.universes u on u.universe_id=br.universe_id
    where u.universe_code='GATE0_NATIVE_CMB_20210830'
    order by br.created_at limit 1
), vr as (
    select run_id,issuer_id,security_id from model.valuation_runs
    where input_hash='58d83f6292e59197fc4effb2bc3f98cd28c80cc4af1cf7af67d20a1b254fc683'
    order by created_at limit 1
)
insert into backtest.decision_events (
    backtest_run_id,decision_at,issuer_id,security_id,valuation_run_id,
    signal,rank_value,target_weight,decision_payload,frozen_at
)
select br.backtest_run_id,'2021-08-30 15:00:00+08',vr.issuer_id,vr.security_id,
       vr.run_id,'avoid_at_price',0.03755026696155135,0.0,
       '{"phase":"A","investment_hurdle":0.15,"pessimistic_irr":-0.07204966900081006,"base_irr":0.03755026696155135,"optimistic_irr":0.13596337615433746,"base_intrinsic_value":36.135509092814395,"optimistic_intrinsic_value":57.67577668835412,"current_price":48.45,"implied_uniform_roe":0.17671456246762313,"data_quality":"provisional","reason":"even optimistic IRR is below hurdle"}'::jsonb,
       now()
from br cross join vr
where not exists (
    select 1 from backtest.decision_events de
    where de.backtest_run_id=br.backtest_run_id
      and de.valuation_run_id=vr.run_id
      and de.decision_at='2021-08-30 15:00:00+08'
);

with decision as (
    select de.decision_id
    from backtest.decision_events de
    join model.valuation_runs vr on vr.run_id=de.valuation_run_id
    where vr.input_hash='58d83f6292e59197fc4effb2bc3f98cd28c80cc4af1cf7af67d20a1b254fc683'
    order by de.frozen_at limit 1
)
insert into backtest.decision_outcomes (
    decision_id,outcome_at,horizon_years,start_price,end_price,
    final_share_multiplier,terminal_value,total_return,annualized_return,
    benchmark_annualized_return,excess_return,source_quality,outcome_payload
)
select decision_id,'2026-08-28 15:00:00+08',5.0,48.45,39.35,
       1.2701437226284904,49.9801554854311,0.03158215656204533,
       0.0062381161097595506,0.0246,-0.01836188389024045,'legacy_proxy',
       '{"phase":"B","corporate_action_count":6,"reinvestment_method":"legacy proxy prices","official_corporate_action_reconciliation_pending":true,"decision_correct_against_15pct_hurdle":true}'::jsonb
from decision
on conflict (decision_id) do update set
    outcome_at=excluded.outcome_at,horizon_years=excluded.horizon_years,
    start_price=excluded.start_price,end_price=excluded.end_price,
    final_share_multiplier=excluded.final_share_multiplier,
    terminal_value=excluded.terminal_value,total_return=excluded.total_return,
    annualized_return=excluded.annualized_return,
    benchmark_annualized_return=excluded.benchmark_annualized_return,
    excess_return=excluded.excess_return,source_quality=excluded.source_quality,
    outcome_payload=excluded.outcome_payload;

with outcome as (
    select o.outcome_id
    from backtest.decision_outcomes o
    join backtest.decision_events de on de.decision_id=o.decision_id
    join model.valuation_runs vr on vr.run_id=de.valuation_run_id
    where vr.input_hash='58d83f6292e59197fc4effb2bc3f98cd28c80cc4af1cf7af67d20a1b254fc683'
), rows(attribution_key,value_numeric,value_text,unit,metadata) as (
    values
    ('native_forecast_error',-0.0313121508517918,null::text,'ratio','{"formula":"actual_annualized_return - native_base_irr"}'::jsonb),
    ('legacy_forecast_error',-0.05156188389024045,null::text,'ratio','{"formula":"actual_annualized_return - legacy_base_irr"}'::jsonb),
    ('price_only_total_return',-0.18782249742002066,null::text,'ratio','{"formula":"end_price / start_price - 1"}'::jsonb),
    ('price_only_annualized_return',-0.04075357112723632,null::text,'ratio','{"formula":"(end_price / start_price)^(1/5)-1"}'::jsonb),
    ('distribution_reinvestment_contribution',0.219404653982066,null::text,'ratio','{"formula":"total_return - price_only_total_return","interpretation":"cumulative contribution proxy"}'::jsonb),
    ('native_minus_legacy_base_value',-4.164490907185602,null::text,'CNY/share','{"native_base":36.135509092814395,"legacy_base":40.30}'::jsonb),
    ('implied_minus_reported_roe',-0.003885437532376884,null::text,'ratio','{"implied_uniform_roe":0.17671456246762313,"reported_annualized_roe":0.1806}'::jsonb),
    ('decision_correct_against_hurdle',null::numeric,'true','boolean','{"hurdle":0.15,"actual_annualized_return":0.0062381161097595506}'::jsonb)
)
insert into backtest.attribution_results (
    outcome_id,attribution_key,value_numeric,value_text,unit,
    methodology_version,metadata
)
select outcome.outcome_id,rows.attribution_key,rows.value_numeric,
       rows.value_text,rows.unit,'endpoint_attribution_v1',rows.metadata
from outcome cross join rows
on conflict (outcome_id,attribution_key,methodology_version) do update set
    value_numeric=excluded.value_numeric,value_text=excluded.value_text,
    unit=excluded.unit,metadata=excluded.metadata;

commit;
