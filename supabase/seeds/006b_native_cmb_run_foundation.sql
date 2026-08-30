begin;

-- Prerequisite evidence must be complete before the model run is admitted.
do $$
begin
    if (select count(*) from pit.financial_facts where record_hash = any(array['4b3c6da762f8405d120984d8e63b2c6e21f943e8ae87e226bd5ba6ae0878f9a4','de37ebe6217d431c268400207b433a8d0de1cbccb055a36485678ade91fb6704','f3c941358b8780df4ac8452690ec9b689ba424072ea0803cef575363fcc5c8ca','72839d63db30841a3a3830cae100418d0a80ef60607c2b48becd32cc86bdd204','78c9a394f2aad8053fcf370b2397c2c7d70f69e0f74f55e54f24862bbf1395f6','f7e3d3dab496170c24484566bb72cf7a87af5bfd0afc63a659e4778624a2136f','58ba2c108ab2007bc29447123fdf0b16b5c65dc67015beabce7a2652f8acf9ff','424aa6de0d42ff542745f77b27e09f74b089877655bf53fb1e65c93b38152e44','f05df37c268540c5604a8def6b206feb7bf76a15f8048cdd423290cce273bb7f','e3853b3d2e3d5fe0a4be2df61ac2c91f56fd24f33c8637cfc0bd7807b207932a','8922e22399aa8db245bcd6beb7bb34968a7ae3b2a6e7b5beee04a3490e09cebb','00b5b99b818ffe4c7b783aedd8504453e57fcf986cdb6b9a6684fbaa4a8778a4'])) <> 12 then
        raise exception 'native CMB financial-fact seed is incomplete';
    end if;
    if (select count(*) from fundamentals.normalized_facts where record_hash = any(array['7ab0ba5db5f74e6cf5557b399e0cae4b90c48f6423f164572f945fa56aeec881','52fb0f4641f8771abbe4ba3eb6e86b9f649699d459257655bda27f90d77a60e8','2649e37e05b105b7a7427090414faa453c147023872879b637622965757931c7','243867c869661b2040de6148b75c804ca627ce7a45e8dcbf4d36e55bfb1b613b','0afac2ddd2d1c4dedea04182613f3f45940581433cce88ee2df4dc4c6926dc0b','16c2f8d582ce74ec0be6b3db930e713f7aed8e40b456a9efdfc775b99d89eb04','05899fb2b022d53b8a93cf42cf999ea1833815efceb90b037e5d2ebcc671be0b','40b9c7d39a4a0a0ad98950e180bc726f2c330d032c03c086aa38bab208ffba8d'])) <> 8 then
        raise exception 'native CMB normalized-fact seed is incomplete';
    end if;
    if not exists (select 1 from audit.data_snapshots where snapshot_hash='8fcc400b62646692ed765323b164ba82941324d3c6252bfb1481d2354d7303f5') then
        raise exception 'native CMB snapshot is missing';
    end if;
end $$;

-- Strengthen the snapshot with the exact content manifest used by the run.
update audit.data_snapshots
set manifest=jsonb_build_object(
    'scope','native_cmb_2021_h1_provisional',
    'issuer_code','CMB',
    'security_code','600036.SH',
    'decision_cutoff','2021-08-30T15:00:00+08:00',
    'eligible_rule','available_at <= decision_cutoff',
    'cutoff_policy_version','pit_cutoff_v1',
    'financial_fact_count',12,
    'financial_fact_hashes',to_jsonb(array['4b3c6da762f8405d120984d8e63b2c6e21f943e8ae87e226bd5ba6ae0878f9a4','de37ebe6217d431c268400207b433a8d0de1cbccb055a36485678ade91fb6704','f3c941358b8780df4ac8452690ec9b689ba424072ea0803cef575363fcc5c8ca','72839d63db30841a3a3830cae100418d0a80ef60607c2b48becd32cc86bdd204','78c9a394f2aad8053fcf370b2397c2c7d70f69e0f74f55e54f24862bbf1395f6','f7e3d3dab496170c24484566bb72cf7a87af5bfd0afc63a659e4778624a2136f','58ba2c108ab2007bc29447123fdf0b16b5c65dc67015beabce7a2652f8acf9ff','424aa6de0d42ff542745f77b27e09f74b089877655bf53fb1e65c93b38152e44','f05df37c268540c5604a8def6b206feb7bf76a15f8048cdd423290cce273bb7f','e3853b3d2e3d5fe0a4be2df61ac2c91f56fd24f33c8637cfc0bd7807b207932a','8922e22399aa8db245bcd6beb7bb34968a7ae3b2a6e7b5beee04a3490e09cebb','00b5b99b818ffe4c7b783aedd8504453e57fcf986cdb6b9a6684fbaa4a8778a4']::text[]),
    'normalized_fact_count',8,
    'normalized_fact_hashes',to_jsonb(array['7ab0ba5db5f74e6cf5557b399e0cae4b90c48f6423f164572f945fa56aeec881','52fb0f4641f8771abbe4ba3eb6e86b9f649699d459257655bda27f90d77a60e8','2649e37e05b105b7a7427090414faa453c147023872879b637622965757931c7','243867c869661b2040de6148b75c804ca627ce7a45e8dcbf4d36e55bfb1b613b','0afac2ddd2d1c4dedea04182613f3f45940581433cce88ee2df4dc4c6926dc0b','16c2f8d582ce74ec0be6b3db930e713f7aed8e40b456a9efdfc775b99d89eb04','05899fb2b022d53b8a93cf42cf999ea1833815efceb90b037e5d2ebcc671be0b','40b9c7d39a4a0a0ad98950e180bc726f2c330d032c03c086aa38bab208ffba8d']::text[]),
    'source_document_count',1,
    'source_document_fingerprints',jsonb_build_array('source_url:https://static.cninfo.com.cn/finalpage/2021-08-14/1210747886.PDF'),
    'market_bar_hash','a621d488cf8a99f1cb57ae24c092404f4415bf1b1e2f05755fc57bcd3559b024',
    'market_close',48.45,
    'market_available_at','2021-08-30T15:00:00+08:00',
    'data_quality','provisional',
    'official_report_binary_archived',false,
    'authoritative_market_bar',false,
    'hash_policies',jsonb_build_array('pit_financial_fact_v1','normalized_fact_explicit_v1','frozen_manifest_sha256_v1')
)
where snapshot_hash='8fcc400b62646692ed765323b164ba82941324d3c6252bfb1481d2354d7303f5';

insert into model.model_versions (
    model_name,semantic_version,model_family,status,git_commit_sha,config_hash,
    effective_from,notes
) values (
    'cmb_residual_income_native','1.0.0','residual_income','validated',
    '12ca182d1c00a0c485c79eb9b483a8111aa213ee',
    '306d4a9c28dedd79e78a184c1df4ffd61efe15261b29593c72f51e97fd4a90ec',
    '2026-08-30 18:54:00+08',
    'Native V1.2 CMB residual-income replay; code validated, evidence and endpoint outcome provisional.'
)
on conflict (model_name,semantic_version) do update set
    model_family=excluded.model_family,status=excluded.status,
    git_commit_sha=excluded.git_commit_sha,config_hash=excluded.config_hash,
    effective_from=excluded.effective_from,notes=excluded.notes;

insert into model.parameter_sets (
    issuer_id,model_family,parameter_version,status,effective_from,
    source_snapshot_id,content_hash,notes,metadata,frozen_at
)
select i.issuer_id,'residual_income','bank_scenario_policy_v1','frozen',
       '2021-08-30 15:00:00+08',ds.snapshot_id,
       '306d4a9c28dedd79e78a184c1df4ffd61efe15261b29593c72f51e97fd4a90ec',
       'Three coherent ten-year ROE/payout/cost-of-equity paths for the native CMB Gate-0 replay.',
       '{"issuer_code":"CMB","decision_at":"2021-08-30T15:00:00+08:00","not_tuned_to_legacy":true}'::jsonb,
       '2026-08-30 18:54:00+08'
from master.issuers i
join audit.data_snapshots ds on ds.snapshot_hash='8fcc400b62646692ed765323b164ba82941324d3c6252bfb1481d2354d7303f5'
where i.issuer_code='CMB'
on conflict ((coalesce(issuer_id,'00000000-0000-0000-0000-000000000000'::uuid)),model_family,parameter_version)
do update set status=excluded.status,effective_from=excluded.effective_from,
    source_snapshot_id=excluded.source_snapshot_id,content_hash=excluded.content_hash,
    notes=excluded.notes,metadata=excluded.metadata,frozen_at=excluded.frozen_at;

with parameter_set as (
    select ps.parameter_set_id
    from model.parameter_sets ps
    join master.issuers i on i.issuer_id=ps.issuer_id
    where i.issuer_code='CMB' and ps.model_family='residual_income'
      and ps.parameter_version='bank_scenario_policy_v1'
), rows(scenario,parameter_key,value_numeric,value_text,value_json,unit,source_kind,provenance) as (
    values
    ('common','current_price',48.45,null,null,'CNY/share','reported_fact','{"record_hash":"a621d488cf8a99f1cb57ae24c092404f4415bf1b1e2f05755fc57bcd3559b024"}'::jsonb),
    ('common','investment_hurdle',0.15,null,null,'ratio','policy','{"policy":"five_year_15pct_hurdle_v1"}'::jsonb),
    ('common','opening_book_value_per_share',26.60,null,null,'CNY/share','normalized_fact','{"record_hash":"7ab0ba5db5f74e6cf5557b399e0cae4b90c48f6423f164572f945fa56aeec881"}'::jsonb),
    ('common','reported_annualized_roe',0.1806,null,null,'ratio','normalized_fact','{"record_hash":"52fb0f4641f8771abbe4ba3eb6e86b9f649699d459257655bda27f90d77a60e8"}'::jsonb),
    ('common','normalization_version',null,'cmb_residual_income_normalization_v1',null,null,'policy','{}'::jsonb),
    ('common','scenario_policy_version',null,'bank_scenario_policy_v1',null,null,'policy','{}'::jsonb),
    ('pessimistic','roe_path',null,null,'[0.145,0.135,0.125,0.115,0.105,0.1,0.095,0.09,0.085,0.08]'::jsonb,'ratio','analyst_judgment','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('pessimistic','payout_ratio_path',null,null,'[0.4,0.4,0.4,0.4,0.4,0.4,0.4,0.4,0.4,0.4]'::jsonb,'ratio','analyst_judgment','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('pessimistic','cost_of_equity',0.12,null,null,'ratio','analyst_judgment','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('pessimistic','terminal_roe',0.095,null,null,'ratio','analyst_judgment','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('pessimistic','terminal_growth',0.02,null,null,'ratio','analyst_judgment','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('base','roe_path',null,null,'[0.17,0.16,0.15,0.14,0.13,0.125,0.12,0.115,0.11,0.105]'::jsonb,'ratio','analyst_judgment','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('base','payout_ratio_path',null,null,'[0.35,0.35,0.35,0.35,0.35,0.35,0.35,0.35,0.35,0.35]'::jsonb,'ratio','analyst_judgment','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('base','cost_of_equity',0.105,null,null,'ratio','analyst_judgment','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('base','terminal_roe',0.115,null,null,'ratio','analyst_judgment','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('base','terminal_growth',0.03,null,null,'ratio','analyst_judgment','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('optimistic','roe_path',null,null,'[0.18,0.175,0.17,0.165,0.16,0.155,0.15,0.145,0.14,0.135]'::jsonb,'ratio','analyst_judgment','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('optimistic','payout_ratio_path',null,null,'[0.32,0.32,0.32,0.32,0.32,0.32,0.32,0.32,0.32,0.32]'::jsonb,'ratio','analyst_judgment','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('optimistic','cost_of_equity',0.095,null,null,'ratio','analyst_judgment','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('optimistic','terminal_roe',0.125,null,null,'ratio','analyst_judgment','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('optimistic','terminal_growth',0.035,null,null,'ratio','analyst_judgment','{"policy":"bank_scenario_policy_v1"}'::jsonb)
)
insert into model.parameter_values (
    parameter_set_id,scenario,parameter_key,value_numeric,value_text,value_json,
    unit,source_kind,provenance
)
select parameter_set.parameter_set_id,rows.scenario,rows.parameter_key,
       rows.value_numeric,rows.value_text,rows.value_json,rows.unit,
       rows.source_kind,rows.provenance
from parameter_set cross join rows
on conflict (parameter_set_id,scenario,parameter_key) do update set
    value_numeric=excluded.value_numeric,value_text=excluded.value_text,
    value_json=excluded.value_json,unit=excluded.unit,
    source_kind=excluded.source_kind,provenance=excluded.provenance;

insert into fundamentals.normalization_runs (
    issuer_id,as_of_at,snapshot_id,normalization_policy_id,status,input_hash,
    output_hash,started_at,completed_at,metadata
)
select i.issuer_id,'2021-08-30 15:00:00+08',ds.snapshot_id,
       np.normalization_policy_id,'completed',
       'acd4bdeb77a38a04129f21a7bae5474cd53e67cc4f976f982460b8aed8c9bb3a',
       'd2502311e4fa5016e9de386305805862e676684b44d756132d89477daa059eb5',
       now(),now(),
       '{"rule_version":"cmb_residual_income_normalization_v1","normalized_fact_count":8}'::jsonb
from master.issuers i
join audit.data_snapshots ds on ds.snapshot_hash='8fcc400b62646692ed765323b164ba82941324d3c6252bfb1481d2354d7303f5'
join fundamentals.normalization_policies np
  on np.policy_code='bank_residual_income_normalization'
 and np.semantic_version='1.0.0'
where i.issuer_code='CMB'
  and not exists (
      select 1 from fundamentals.normalization_runs nr
      where nr.issuer_id=i.issuer_id
        and nr.as_of_at='2021-08-30 15:00:00+08'
        and nr.normalization_policy_id=np.normalization_policy_id
        and nr.input_hash='acd4bdeb77a38a04129f21a7bae5474cd53e67cc4f976f982460b8aed8c9bb3a'
  );

insert into model.valuation_runs (
    issuer_id,security_id,as_of_at,snapshot_id,model_version_id,
    scenario_set_version,status,started_at,completed_at,input_hash,output_hash,
    validation_status,allocation_eligibility
)
select i.issuer_id,s.security_id,'2021-08-30 15:00:00+08',ds.snapshot_id,
       mv.model_version_id,'bank_scenario_policy_v1','succeeded',now(),now(),
       '58d83f6292e59197fc4effb2bc3f98cd28c80cc4af1cf7af67d20a1b254fc683',
       '6d14a8ce6b78384daa466a7e673c3ecd4c73d487198856e19d8346af24ed2104',
       'passed_with_warnings','research_only'
from master.issuers i
join master.securities s on s.issuer_id=i.issuer_id and s.security_code='600036.SH'
join audit.data_snapshots ds on ds.snapshot_hash='8fcc400b62646692ed765323b164ba82941324d3c6252bfb1481d2354d7303f5'
join model.model_versions mv
  on mv.model_name='cmb_residual_income_native'
 and mv.semantic_version='1.0.0'
where i.issuer_code='CMB'
  and not exists (
      select 1 from model.valuation_runs vr
      where vr.input_hash='58d83f6292e59197fc4effb2bc3f98cd28c80cc4af1cf7af67d20a1b254fc683'
  );

update model.valuation_runs
set snapshot_id=(select snapshot_id from audit.data_snapshots
                 where snapshot_hash='8fcc400b62646692ed765323b164ba82941324d3c6252bfb1481d2354d7303f5'),
    output_hash='6d14a8ce6b78384daa466a7e673c3ecd4c73d487198856e19d8346af24ed2104',
    status='succeeded',validation_status='passed_with_warnings',
    allocation_eligibility='research_only'
where input_hash='58d83f6292e59197fc4effb2bc3f98cd28c80cc4af1cf7af67d20a1b254fc683';

with run as (
    select run_id from model.valuation_runs
    where input_hash='58d83f6292e59197fc4effb2bc3f98cd28c80cc4af1cf7af67d20a1b254fc683'
    order by created_at limit 1
), rows(scenario,assumption_key,value_numeric,value_text,value_json,unit,source_kind,provenance) as (
    values
    ('common','current_price',48.45,null,null,'CNY/share','market_fact','{"record_hash":"a621d488cf8a99f1cb57ae24c092404f4415bf1b1e2f05755fc57bcd3559b024"}'::jsonb),
    ('common','investment_hurdle',0.15,null,null,'ratio','model_policy','{"policy":"five_year_15pct_hurdle_v1"}'::jsonb),
    ('common','opening_book_value_per_share',26.60,null,null,'CNY/share','normalized_fact','{"record_hash":"7ab0ba5db5f74e6cf5557b399e0cae4b90c48f6423f164572f945fa56aeec881"}'::jsonb),
    ('common','reported_annualized_roe',0.1806,null,null,'ratio','normalized_fact','{"record_hash":"52fb0f4641f8771abbe4ba3eb6e86b9f649699d459257655bda27f90d77a60e8"}'::jsonb),
    ('common','normalization_version',null,'cmb_residual_income_normalization_v1',null,null,'model_policy','{}'::jsonb),
    ('common','scenario_policy_version',null,'bank_scenario_policy_v1',null,null,'model_policy','{}'::jsonb),
    ('pessimistic','roe_path',null,null,'[0.145,0.135,0.125,0.115,0.105,0.1,0.095,0.09,0.085,0.08]'::jsonb,'ratio','scenario_policy','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('pessimistic','payout_ratio_path',null,null,'[0.4,0.4,0.4,0.4,0.4,0.4,0.4,0.4,0.4,0.4]'::jsonb,'ratio','scenario_policy','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('pessimistic','cost_of_equity',0.12,null,null,'ratio','scenario_policy','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('pessimistic','terminal_roe',0.095,null,null,'ratio','scenario_policy','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('pessimistic','terminal_growth',0.02,null,null,'ratio','scenario_policy','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('base','roe_path',null,null,'[0.17,0.16,0.15,0.14,0.13,0.125,0.12,0.115,0.11,0.105]'::jsonb,'ratio','scenario_policy','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('base','payout_ratio_path',null,null,'[0.35,0.35,0.35,0.35,0.35,0.35,0.35,0.35,0.35,0.35]'::jsonb,'ratio','scenario_policy','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('base','cost_of_equity',0.105,null,null,'ratio','scenario_policy','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('base','terminal_roe',0.115,null,null,'ratio','scenario_policy','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('base','terminal_growth',0.03,null,null,'ratio','scenario_policy','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('optimistic','roe_path',null,null,'[0.18,0.175,0.17,0.165,0.16,0.155,0.15,0.145,0.14,0.135]'::jsonb,'ratio','scenario_policy','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('optimistic','payout_ratio_path',null,null,'[0.32,0.32,0.32,0.32,0.32,0.32,0.32,0.32,0.32,0.32]'::jsonb,'ratio','scenario_policy','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('optimistic','cost_of_equity',0.095,null,null,'ratio','scenario_policy','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('optimistic','terminal_roe',0.125,null,null,'ratio','scenario_policy','{"policy":"bank_scenario_policy_v1"}'::jsonb),
    ('optimistic','terminal_growth',0.035,null,null,'ratio','scenario_policy','{"policy":"bank_scenario_policy_v1"}'::jsonb)
)
insert into model.run_assumptions (
    run_id,scenario,assumption_key,value_numeric,value_text,value_json,unit,
    source_kind,provenance
)
select run.run_id,rows.scenario,rows.assumption_key,rows.value_numeric,
       rows.value_text,rows.value_json,rows.unit,rows.source_kind,rows.provenance
from run cross join rows
on conflict (run_id,scenario,assumption_key) do update set
    value_numeric=excluded.value_numeric,value_text=excluded.value_text,
    value_json=excluded.value_json,unit=excluded.unit,
    source_kind=excluded.source_kind,provenance=excluded.provenance;

commit;
