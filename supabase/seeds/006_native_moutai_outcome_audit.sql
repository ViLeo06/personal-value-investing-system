begin;

insert into backtest.universes (
    universe_code,name,description,construction_policy_version
) values (
    'GATE0_NATIVE_MOUTAI_20210830',
    'Gate 0 native Moutai 2021-08-30 replay',
    'Single-security native PIT replay validating evidence, normalization, valuation, decision freeze, outcome and attribution contracts.',
    'single_security_native_v1'
)
on conflict (universe_code) do update set
    name=excluded.name,
    description=excluded.description,
    construction_policy_version=excluded.construction_policy_version;

insert into backtest.universe_memberships (
    universe_id,security_id,valid_from,valid_to,eligibility_reason
)
select u.universe_id,s.security_id,'2001-08-27',null,
       '{"reason":"Gate 0 named validation security","selection_is_not_point_in_time_universe_sample":true}'::jsonb
from backtest.universes u
join master.securities s on s.security_code='600519.SH'
where u.universe_code='GATE0_NATIVE_MOUTAI_20210830'
  and not exists (
      select 1 from backtest.universe_memberships um
      where um.universe_id=u.universe_id and um.security_id=s.security_id
        and um.valid_from='2001-08-27' and um.valid_to is null
  );

insert into backtest.backtest_runs (
    universe_id,model_version_id,start_date,end_date,holding_horizon_months,
    configuration,git_commit_sha,status,started_at,completed_at,result_hash
)
select u.universe_id,mv.model_version_id,'2021-08-30','2026-08-28',60,
       '{"mode":"single_security_counterfactual_endpoint_replay","phase_a_frozen":true,"phase_b_separate_table":true,"daily_performance_loaded":false,"corporate_action_source":"legacy_proxy_pending_official_replacement","investment_hurdle":0.15}'::jsonb,
       '87f32ab7c342f5648b1e72741458e4962baa53a2','succeeded',now(),now(),
       'dfd8f0d412e5b3d763a66d8722e25636d548e5d51b9baa241f4b82eeca9bda86'
from backtest.universes u
join model.model_versions mv on mv.model_name='moutai_owner_earnings_native'
 and mv.semantic_version='1.0.0'
where u.universe_code='GATE0_NATIVE_MOUTAI_20210830'
  and not exists (
      select 1 from backtest.backtest_runs br
      where br.universe_id=u.universe_id and br.model_version_id=mv.model_version_id
        and br.start_date='2021-08-30' and br.end_date='2026-08-28'
        and br.result_hash='dfd8f0d412e5b3d763a66d8722e25636d548e5d51b9baa241f4b82eeca9bda86'
  );

with br as (
    select br.backtest_run_id
    from backtest.backtest_runs br
    join backtest.universes u on u.universe_id=br.universe_id
    where u.universe_code='GATE0_NATIVE_MOUTAI_20210830'
    order by br.created_at limit 1
), vr as (
    select run_id,issuer_id,security_id
    from model.valuation_runs
    where input_hash='73e174fa57695eeaf2f36a12eeab7afaa85ac7d31927c0f155145e29becaaf89'
    order by created_at limit 1
)
insert into backtest.decision_events (
    backtest_run_id,decision_at,issuer_id,security_id,valuation_run_id,
    signal,rank_value,target_weight,decision_payload,frozen_at
)
select br.backtest_run_id,'2021-08-30 15:00:00+08',vr.issuer_id,vr.security_id,
       vr.run_id,'avoid_at_price',-0.023967490793221462,0.0,
       '{"phase":"A","investment_hurdle":0.15,"pessimistic_irr":-0.15658568617388613,"base_irr":-0.023967490793221462,"optimistic_irr":0.06204820355188434,"base_intrinsic_value":930.5299864767308,"optimistic_intrinsic_value":1435.342514370947,"current_price":1586.0,"data_quality":"provisional","reason":"even optimistic IRR is below hurdle"}'::jsonb,
       now()
from br cross join vr
where not exists (
    select 1 from backtest.decision_events de
    where de.backtest_run_id=br.backtest_run_id and de.valuation_run_id=vr.run_id
      and de.decision_at='2021-08-30 15:00:00+08'
);

with decision as (
    select de.decision_id
    from backtest.decision_events de
    join model.valuation_runs vr on vr.run_id=de.valuation_run_id
    where vr.input_hash='73e174fa57695eeaf2f36a12eeab7afaa85ac7d31927c0f155145e29becaaf89'
    order by de.frozen_at limit 1
)
insert into backtest.decision_outcomes (
    decision_id,outcome_at,horizon_years,start_price,end_price,
    final_share_multiplier,terminal_value,total_return,annualized_return,
    benchmark_annualized_return,excess_return,source_quality,outcome_payload
)
select decision_id,'2026-08-28 15:00:00+08',5.0,1586.0,1297.4,
       1.1566638034040813,1500.6556185364552,-0.053811085412071136,
       -0.01100164070499099,0.0246,-0.035601640704990986,'legacy_proxy',
       '{"phase":"B","corporate_action_count":9,"reinvestment_method":"legacy proxy prices","official_corporate_action_reconciliation_pending":true,"decision_correct_against_15pct_hurdle":true}'::jsonb
from decision
on conflict (decision_id) do update set
    outcome_at=excluded.outcome_at,
    horizon_years=excluded.horizon_years,
    start_price=excluded.start_price,
    end_price=excluded.end_price,
    final_share_multiplier=excluded.final_share_multiplier,
    terminal_value=excluded.terminal_value,
    total_return=excluded.total_return,
    annualized_return=excluded.annualized_return,
    benchmark_annualized_return=excluded.benchmark_annualized_return,
    excess_return=excluded.excess_return,
    source_quality=excluded.source_quality,
    outcome_payload=excluded.outcome_payload;

with outcome as (
    select o.outcome_id
    from backtest.decision_outcomes o
    join backtest.decision_events de on de.decision_id=o.decision_id
    join model.valuation_runs vr on vr.run_id=de.valuation_run_id
    where vr.input_hash='73e174fa57695eeaf2f36a12eeab7afaa85ac7d31927c0f155145e29becaaf89'
), rows(attribution_key,value_numeric,value_text,unit,metadata) as (
    values
    ('native_forecast_error',0.012965850088230473,null::text,'ratio','{"formula":"actual_annualized_return - native_base_irr"}'::jsonb),
    ('legacy_forecast_error',-0.05660164070499099,null::text,'ratio','{"formula":"actual_annualized_return - legacy_base_irr"}'::jsonb),
    ('price_only_total_return',-0.18196721311475406,null::text,'ratio','{"formula":"end_price / start_price - 1"}'::jsonb),
    ('price_only_annualized_return',-0.03937443091971293,null::text,'ratio','{"formula":"(end_price / start_price)^(1/5)-1"}'::jsonb),
    ('distribution_reinvestment_contribution',0.12815612770268292,null::text,'ratio','{"formula":"total_return - price_only_total_return","interpretation":"cumulative contribution proxy"}'::jsonb),
    ('native_minus_legacy_base_value',-502.9300135232692,null::text,'CNY/share','{"native_base":930.5299864767308,"legacy_base":1433.46}'::jsonb),
    ('decision_correct_against_hurdle',null::numeric,'true','boolean','{"hurdle":0.15,"actual_annualized_return":-0.01100164070499099}'::jsonb)
)
insert into backtest.attribution_results (
    outcome_id,attribution_key,value_numeric,value_text,unit,
    methodology_version,metadata
)
select outcome.outcome_id,rows.attribution_key,rows.value_numeric,rows.value_text,
       rows.unit,'endpoint_attribution_v1',rows.metadata
from outcome cross join rows
on conflict (outcome_id,attribution_key,methodology_version) do update set
    value_numeric=excluded.value_numeric,
    value_text=excluded.value_text,
    unit=excluded.unit,
    metadata=excluded.metadata;

-- Stable valuation lineage. Input IDs use hashes or natural keys rather than generated IDs.
with vr as (
    select vr.run_id,vr.model_version_id,vr.security_id,vr.snapshot_id
    from model.valuation_runs vr
    where vr.input_hash='73e174fa57695eeaf2f36a12eeab7afaa85ac7d31927c0f155145e29becaaf89'
    order by vr.created_at limit 1
), inputs(input_type,input_id,input_hash,metadata) as (
    values
    ('data_snapshot','68a8590234c749dcf272a156d1afc74cebea9dc78e5e686ca0bc88eb2915f027','68a8590234c749dcf272a156d1afc74cebea9dc78e5e686ca0bc88eb2915f027','{"active":true,"scope":"native_moutai_2021_phase_a_v4_frozen_manifest"}'::jsonb),
    ('git_commit','87f32ab7c342f5648b1e72741458e4962baa53a2','87f32ab7c342f5648b1e72741458e4962baa53a2','{"role":"tested_native_model_commit"}'::jsonb),
    ('normalization_version','moutai_owner_earnings_normalization_v1',null,'{}'::jsonb),
    ('scenario_policy','consumer_scenario_policy_v1',null,'{"explicit_years":15,"fade_start_year":4}'::jsonb),
    ('market_bar','d8e3c33cfa5aabf5727ebc0a4ed93763e34041d5f4833c6af11c650c0bed1bf8','d8e3c33cfa5aabf5727ebc0a4ed93763e34041d5f4833c6af11c650c0bed1bf8','{"security_code":"600519.SH","trade_date":"2021-08-30","close":1586.0}'::jsonb),
    ('source_document','source_url:https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2021-03-31/600519_20210331_1.pdf',null,'{"document_type":"annual_report"}'::jsonb),
    ('source_document','8527c8faba38d77c8ecdc13a4e567b9424940440790528921a93f43a16f06011','8527c8faba38d77c8ecdc13a4e567b9424940440790528921a93f43a16f06011','{"document_type":"half_year_publication"}'::jsonb),
    ('source_document','709543434cc77e94aeb9a01a48a02bd8335fb016f04436f0ac6bc18bf0a11d71','709543434cc77e94aeb9a01a48a02bd8335fb016f04436f0ac6bc18bf0a11d71','{"document_type":"half_year_numeric_archive"}'::jsonb),
    ('normalized_fact','74b6c7ef463fd636a0a18975d549faf41513c345c0308f6a5d26d90a01bea5c1','74b6c7ef463fd636a0a18975d549faf41513c345c0308f6a5d26d90a01bea5c1','{"metric_code":"shares_outstanding_inferred"}'::jsonb),
    ('normalized_fact','3f07ced3ced89ee1786050056e477957da209610169c9cb65190841560c7585c','3f07ced3ced89ee1786050056e477957da209610169c9cb65190841560c7585c','{"metric_code":"owner_earnings_per_share"}'::jsonb),
    ('normalized_fact','86f00df1681137c2062a53a9c94e2649697067b918bb5e86d178b05ff3e88d65','86f00df1681137c2062a53a9c94e2649697067b918bb5e86d178b05ff3e88d65','{"metric_code":"growth_anchor"}'::jsonb),
    ('normalized_fact','b8c43d080c52ee00cb9ae19f9788d9ca8359e4507fb1cdf8abc6e08e8a9b8c09','b8c43d080c52ee00cb9ae19f9788d9ca8359e4507fb1cdf8abc6e08e8a9b8c09','{"metric_code":"cash_conversion_ratio","period":"2020FY"}'::jsonb),
    ('normalized_fact','e828effd82ef64e1b29298b6e018b0fe8801f49bcc15f4878364a733581822cc','e828effd82ef64e1b29298b6e018b0fe8801f49bcc15f4878364a733581822cc','{"metric_code":"cash_conversion_ratio","period":"2021H1"}'::jsonb)
)
insert into audit.run_lineage (
    run_type,run_id,input_type,input_id,input_hash,metadata
)
select 'valuation',vr.run_id,inputs.input_type,inputs.input_id,
       inputs.input_hash,inputs.metadata
from vr cross join inputs
where not exists (
    select 1 from audit.run_lineage rl
    where rl.run_type='valuation' and rl.run_id=vr.run_id
      and rl.input_type=inputs.input_type and rl.input_id=inputs.input_id
);

with br as (
    select br.backtest_run_id
    from backtest.backtest_runs br
    join backtest.universes u on u.universe_id=br.universe_id
    where u.universe_code='GATE0_NATIVE_MOUTAI_20210830'
    order by br.created_at limit 1
), native as (
    select vr.run_id,de.decision_id,o.outcome_id
    from model.valuation_runs vr
    join backtest.decision_events de on de.valuation_run_id=vr.run_id
    join backtest.decision_outcomes o on o.decision_id=de.decision_id
    where vr.input_hash='73e174fa57695eeaf2f36a12eeab7afaa85ac7d31927c0f155145e29becaaf89'
), inputs(input_type,input_id,input_hash,metadata) as (
    select 'valuation_run',native.run_id::text,'98817cf2e591fa075812bf84984aad29ccc32dbca7af62d73515ca1a14be4bd3','{"phase":"A"}'::jsonb from native
    union all select 'decision_event',native.decision_id::text,null,'{"signal":"avoid_at_price","target_weight":0}'::jsonb from native
    union all select 'decision_outcome',native.outcome_id::text,null,'{"phase":"B","source_quality":"legacy_proxy"}'::jsonb from native
    union all select 'corporate_action_ledger','600519.SH:2022-06:2026-06','legacy_proxy','{"event_count":9,"official_reconciliation_pending":true}'::jsonb from native
    union all select 'benchmark_proxy','CSI300_total_return_proxy_2021_2026','0.0246','{"annualized_return":0.0246,"exact_window_alignment":false}'::jsonb from native
)
insert into audit.run_lineage (
    run_type,run_id,input_type,input_id,input_hash,metadata
)
select 'backtest',br.backtest_run_id,inputs.input_type,inputs.input_id,
       inputs.input_hash,inputs.metadata
from br cross join inputs
where not exists (
    select 1 from audit.run_lineage rl
    where rl.run_type='backtest' and rl.run_id=br.backtest_run_id
      and rl.input_type=inputs.input_type and rl.input_id=inputs.input_id
);

with native as (
    select vr.run_id,o.outcome_id
    from model.valuation_runs vr
    join backtest.decision_events de on de.valuation_run_id=vr.run_id
    join backtest.decision_outcomes o on o.decision_id=de.decision_id
    where vr.input_hash='73e174fa57695eeaf2f36a12eeab7afaa85ac7d31927c0f155145e29becaaf89'
), issues(severity,domain,table_name,record_key,rule_code,description,details) as (
    values
    ('warning','evidence','raw.documents',(select run_id::text from native),'DERIVED_ARCHIVE_INPUT','2021H1 numeric evidence is cross-checked through free archives rather than a locally preserved official filing binary.','{"required_remediation":"download and hash official filing","automatic_allocation_eligible":false}'::jsonb),
    ('warning','market_data','pit.market_bars',(select run_id::text from native),'PROVISIONAL_HISTORICAL_CLOSE','The 2021-08-30 close is not yet backed by an authoritative daily market-data file.','{"security_code":"600519.SH","close":1586.0}'::jsonb),
    ('warning','normalization','fundamentals.normalized_facts',(select run_id::text from native),'MAINTENANCE_CAPEX_PROXY','Owner earnings uses a fixed 5% maintenance-capital reserve.','{"factor":0.95}'::jsonb),
    ('warning','backtest','backtest.decision_outcomes',(select outcome_id::text from native),'CORPORATE_ACTION_PROXY_LEDGER','Phase B total return uses proxy dividend reinvestment prices from the legacy workbook.','{"event_count":9,"source_quality":"legacy_proxy"}'::jsonb),
    ('info','forecast','model.run_assumptions',(select run_id::text from native),'NO_BROKER_FORECAST_ARCHIVE','The native run omits unpreserved timestamped broker-consensus forecasts.','{"effect":"disclosure-only growth anchor"}'::jsonb),
    ('info','evidence','raw.documents',(select run_id::text from native),'COARSE_ANNUAL_PUBLICATION_TIME','The 2020 annual report publication time has date-level precision.','{"published_date":"2021-03-31"}'::jsonb),
    ('warning','backtest','backtest.daily_performance',(select outcome_id::text from native),'DAILY_TOTAL_RETURN_SERIES_MISSING','A reconciled daily total-return series and maximum drawdown are not loaded.','{"mdd_scored":false}'::jsonb)
)
insert into audit.data_quality_issues (
    severity,domain,table_name,record_key,rule_code,description,status,details
)
select severity,domain,table_name,record_key,rule_code,description,'open',details
from issues
where not exists (
    select 1 from audit.data_quality_issues dqi
    where dqi.rule_code=issues.rule_code and dqi.record_key=issues.record_key
);

commit;
