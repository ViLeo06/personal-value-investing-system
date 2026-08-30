begin;

with vr as (
    select run_id from model.valuation_runs
    where input_hash='58d83f6292e59197fc4effb2bc3f98cd28c80cc4af1cf7af67d20a1b254fc683'
    order by created_at limit 1
), inputs(input_type,input_id,input_hash,metadata) as (
    values
    ('data_snapshot','8fcc400b62646692ed765323b164ba82941324d3c6252bfb1481d2354d7303f5','8fcc400b62646692ed765323b164ba82941324d3c6252bfb1481d2354d7303f5','{"scope":"native_cmb_2021_h1_provisional"}'::jsonb),
    ('git_commit','12ca182d1c00a0c485c79eb9b483a8111aa213ee','12ca182d1c00a0c485c79eb9b483a8111aa213ee','{"role":"tested_native_model_commit"}'::jsonb),
    ('parameter_set','306d4a9c28dedd79e78a184c1df4ffd61efe15261b29593c72f51e97fd4a90ec','306d4a9c28dedd79e78a184c1df4ffd61efe15261b29593c72f51e97fd4a90ec','{"version":"bank_scenario_policy_v1"}'::jsonb),
    ('normalization_version','cmb_residual_income_normalization_v1',null,'{}'::jsonb),
    ('market_bar','a621d488cf8a99f1cb57ae24c092404f4415bf1b1e2f05755fc57bcd3559b024','a621d488cf8a99f1cb57ae24c092404f4415bf1b1e2f05755fc57bcd3559b024','{"close":48.45,"security_code":"600036.SH","trade_date":"2021-08-30"}'::jsonb),
    ('source_document','source_url:https://static.cninfo.com.cn/finalpage/2021-08-14/1210747886.PDF',null,'{"binary_archived":false,"document_type":"half_year_report"}'::jsonb),
    ('normalized_fact','7ab0ba5db5f74e6cf5557b399e0cae4b90c48f6423f164572f945fa56aeec881','7ab0ba5db5f74e6cf5557b399e0cae4b90c48f6423f164572f945fa56aeec881','{"metric_code":"book_value_per_share"}'::jsonb),
    ('normalized_fact','52fb0f4641f8771abbe4ba3eb6e86b9f649699d459257655bda27f90d77a60e8','52fb0f4641f8771abbe4ba3eb6e86b9f649699d459257655bda27f90d77a60e8','{"metric_code":"roe"}'::jsonb),
    ('normalized_fact','2649e37e05b105b7a7427090414faa453c147023872879b637622965757931c7','2649e37e05b105b7a7427090414faa453c147023872879b637622965757931c7','{"metric_code":"annualized_eps"}'::jsonb),
    ('normalized_fact','243867c869661b2040de6148b75c804ca627ce7a45e8dcbf4d36e55bfb1b613b','243867c869661b2040de6148b75c804ca627ce7a45e8dcbf4d36e55bfb1b613b','{"metric_code":"net_interest_margin"}'::jsonb),
    ('normalized_fact','0afac2ddd2d1c4dedea04182613f3f45940581433cce88ee2df4dc4c6926dc0b','0afac2ddd2d1c4dedea04182613f3f45940581433cce88ee2df4dc4c6926dc0b','{"metric_code":"credit_cost"}'::jsonb),
    ('normalized_fact','16c2f8d582ce74ec0be6b3db930e713f7aed8e40b456a9efdfc775b99d89eb04','16c2f8d582ce74ec0be6b3db930e713f7aed8e40b456a9efdfc775b99d89eb04','{"metric_code":"cost_income_ratio"}'::jsonb),
    ('normalized_fact','05899fb2b022d53b8a93cf42cf999ea1833815efceb90b037e5d2ebcc671be0b','05899fb2b022d53b8a93cf42cf999ea1833815efceb90b037e5d2ebcc671be0b','{"metric_code":"non_performing_loan_ratio"}'::jsonb),
    ('normalized_fact','40b9c7d39a4a0a0ad98950e180bc726f2c330d032c03c086aa38bab208ffba8d','40b9c7d39a4a0a0ad98950e180bc726f2c330d032c03c086aa38bab208ffba8d','{"metric_code":"common_equity_tier1_ratio"}'::jsonb)
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

with vr as (
    select run_id::text as target_id from model.valuation_runs
    where input_hash='58d83f6292e59197fc4effb2bc3f98cd28c80cc4af1cf7af67d20a1b254fc683'
    order by created_at limit 1
)
insert into audit.validation_runs (
    target_type,target_id,ruleset_version,status,report_hash,
    started_at,completed_at,metadata
)
select 'valuation_run',target_id,'gate0_validation_v1.0.0',
       'passed_with_warnings',
       'f9a0f6f15a4bb90487b5cca32337144056987dea13d4b21baaa167e089f5d9e6',
       now(),now(),
       '{"issuer_code":"CMB","decision_at":"2021-08-30T15:00:00+08:00"}'::jsonb
from vr
on conflict (target_type,target_id,ruleset_version) do update set
    status=excluded.status,report_hash=excluded.report_hash,
    completed_at=excluded.completed_at,metadata=excluded.metadata;

with validation as (
    select v.validation_run_id
    from audit.validation_runs v
    join model.valuation_runs vr on vr.run_id::text=v.target_id
    where vr.input_hash='58d83f6292e59197fc4effb2bc3f98cd28c80cc4af1cf7af67d20a1b254fc683'
      and v.ruleset_version='gate0_validation_v1.0.0'
), rows(rule_code,severity,passed,message,details) as (
    values
    ('PIT_NO_FUTURE_LEAKAGE','critical',true,'All selected facts satisfy available_at <= decision_at.','{"leaked_rows":0}'::jsonb),
    ('REQUIRED_FACT_COUNT','error',true,'The native CMB snapshot contains 12 required PIT facts.','{"expected":12,"actual":12}'::jsonb),
    ('NORMALIZED_FACT_COUNT','error',true,'The native CMB normalization contains 8 facts.','{"expected":8,"actual":8}'::jsonb),
    ('OUTPUT_HASH_MATCH','error',true,'Stored output hash matches the deterministic native run.','{"output_hash":"6d14a8ce6b78384daa466a7e673c3ecd4c73d487198856e19d8346af24ed2104"}'::jsonb),
    ('OFFICIAL_BINARY_ARCHIVED','warning',false,'Official PDF URL is verified but exact bytes are not retained and hashed.','{"source_url":"https://static.cninfo.com.cn/finalpage/2021-08-14/1210747886.PDF"}'::jsonb),
    ('AUTHORITATIVE_MARKET_BAR','warning',false,'The 2021-08-30 close is still a legacy-workbook proxy.','{"price":48.45,"record_hash":"a621d488cf8a99f1cb57ae24c092404f4415bf1b1e2f05755fc57bcd3559b024"}'::jsonb),
    ('OFFICIAL_CORPORATE_ACTION_LEDGER','warning',false,'The Phase-B dividend ledger uses proxy dates and reinvestment prices.','{"corporate_action_count":6}'::jsonb),
    ('DAILY_TOTAL_RETURN_SERIES','warning',false,'Daily total-return history and drawdown are not loaded.','{"endpoint_only":true}'::jsonb)
)
insert into audit.validation_results (
    validation_run_id,rule_code,severity,passed,message,details
)
select validation.validation_run_id,rows.rule_code,rows.severity,rows.passed,
       rows.message,rows.details
from validation cross join rows
on conflict (validation_run_id,rule_code) do update set
    severity=excluded.severity,passed=excluded.passed,message=excluded.message,
    details=excluded.details,evaluated_at=now();

with vr as (
    select run_id from model.valuation_runs
    where input_hash='58d83f6292e59197fc4effb2bc3f98cd28c80cc4af1cf7af67d20a1b254fc683'
    order by created_at limit 1
), qrs as (
    select quality_rule_set_id from audit.quality_rule_sets
    where rule_set_version='gate0_quality_v1.0.0'
), rows(rule_code,severity,passed,details) as (
    values
    ('PIT_NO_FUTURE_LEAKAGE','critical',true,'{"leaked_rows":0}'::jsonb),
    ('REQUIRED_SOURCE_PROVENANCE','error',true,'{"document_reference":true,"normalized_lineage":true}'::jsonb),
    ('OFFICIAL_BINARY_ARCHIVED','warning',false,'{"binary_archived":false}'::jsonb),
    ('AUTHORITATIVE_MARKET_BAR','warning',false,'{"proxy":true}'::jsonb),
    ('OFFICIAL_CORPORATE_ACTION_LEDGER','warning',false,'{"proxy":true}'::jsonb),
    ('DAILY_TOTAL_RETURN_SERIES','warning',false,'{"loaded":false}'::jsonb)
)
insert into audit.run_quality_results (
    run_type,run_id,quality_rule_set_id,rule_code,severity,passed,details
)
select 'valuation',vr.run_id,qrs.quality_rule_set_id,rows.rule_code,
       rows.severity,rows.passed,rows.details
from vr cross join qrs cross join rows
on conflict (run_type,run_id,quality_rule_set_id,rule_code) do update set
    severity=excluded.severity,passed=excluded.passed,
    details=excluded.details,checked_at=now();

with vr as (
    select run_id from model.valuation_runs
    where input_hash='58d83f6292e59197fc4effb2bc3f98cd28c80cc4af1cf7af67d20a1b254fc683'
    order by created_at limit 1
), qrs as (
    select quality_rule_set_id from audit.quality_rule_sets
    where rule_set_version='gate0_quality_v1.0.0'
)
insert into audit.run_readiness (
    run_type,run_id,quality_rule_set_id,readiness,summary,assessed_at
)
select 'valuation',vr.run_id,qrs.quality_rule_set_id,'provisional',
       '{"passed_critical_rules":true,"allocation_eligibility":"research_only","warnings":["official_binary_not_archived","historical_close_proxy","corporate_action_proxy","daily_total_return_missing"]}'::jsonb,
       now()
from vr cross join qrs
on conflict (run_type,run_id,quality_rule_set_id) do update set
    readiness=excluded.readiness,summary=excluded.summary,
    assessed_at=excluded.assessed_at;

with rows(severity,domain,table_name,record_key,rule_code,description,status,details) as (
    values
    ('warning','evidence','raw.documents','CMB:2021-08-30:native','OFFICIAL_BINARY_NOT_ARCHIVED','Official filing URL is registered, but the exact PDF bytes have not been retained and hashed.','open','{"source_url":"https://static.cninfo.com.cn/finalpage/2021-08-14/1210747886.PDF"}'::jsonb),
    ('warning','market_data','pit.market_bars','CMB:2021-08-30:native','PROVISIONAL_HISTORICAL_CLOSE','Historical close is sourced from the legacy workbook pending authoritative daily market data.','open','{"close":48.45}'::jsonb),
    ('warning','backtest','pit.corporate_actions','CMB:2021-08-30:native','CORPORATE_ACTION_PROXY_LEDGER','Dividend dates and reinvestment prices are proxy observations.','open','{"corporate_action_count":6}'::jsonb),
    ('warning','backtest','backtest.daily_performance','CMB:2021-08-30:native','DAILY_TOTAL_RETURN_SERIES_MISSING','Only endpoint total return is available; drawdown cannot yet be calculated.','open','{"endpoint_only":true}'::jsonb),
    ('info','forecast','model.run_assumptions','CMB:2021-08-30:native','BANK_SCENARIO_PRIORS_POLICY_ONLY','ROE, payout and cost-of-equity paths are explicit policy judgments pending a free empirical-prior dataset.','open','{"parameter_set_hash":"306d4a9c28dedd79e78a184c1df4ffd61efe15261b29593c72f51e97fd4a90ec"}'::jsonb)
)
insert into audit.data_quality_issues (
    severity,domain,table_name,record_key,rule_code,description,status,details
)
select rows.severity,rows.domain,rows.table_name,rows.record_key,rows.rule_code,
       rows.description,rows.status,rows.details
from rows
where not exists (
    select 1 from audit.data_quality_issues d
    where d.record_key=rows.record_key and d.rule_code=rows.rule_code
      and d.status in ('open','acknowledged')
);

commit;
