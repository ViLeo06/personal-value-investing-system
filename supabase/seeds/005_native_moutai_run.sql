begin;

-- Fail fast when prerequisite evidence seeds are incomplete.
do $$
begin
    if (select count(*) from pit.financial_facts
        where record_hash in (
            '1a5f723fe27e086f3a5dc7c44f2d07a920dc3e9e65af87b430b00c9ad896b509',
            '1337b52e09f127c4f86281714a28c7e8dd04a8abb21a8e1f807d1d51bb786ffa',
            'd42d6071c2df12bb975c7f72c8acc861f2bfea06c89614e3a0579324234270d9',
            '40e3bc475f7166c29d7f5d10d4f4e259ee1a5bdf8b474dba870c003770a3d5b1',
            'd5b05f66d74be87e35b8ad7e13fc6a18b3552db014a71a0cc14ae352793322ea',
            '0ab47ad9dd4b4b5153f5cbcadefbfeaf010295dbf8b2af8104465f1938a11e20',
            '82526a93a218d4d5bcbd2e20eda762c939f04d333bd283c4d9cf278d23a78f54',
            '0d3dd3232a86b6a90cd9527bdc7d73220e85a053afc3021930def793e1628d48',
            '5330df5e8985745b73bf7f280071e353a1a39e0be8f0cb4912a19a4aaaf4582d',
            '14dd3ac9b283fe85690d087578a5008aad063be86aa360a9c998965ba26e8c6a',
            '406a83c52b588c9649f3b806f9082c344629c30cd50eea2a7f5153b032f1afd5',
            '189ed7402ee994aec87a21db5dafdb848c00f3acf4d093f26e3f49a4bb2cf337',
            '53753b17a1781bd01d2fbb60113ceb1aa2197fbf89d51afeb6ffa53a2e6fda3d'
        )) <> 13 then
        raise exception 'native Moutai financial-fact seed is incomplete';
    end if;
    if (select count(*) from fundamentals.normalized_facts
        where record_hash in (
            'b8c43d080c52ee00cb9ae19f9788d9ca8359e4507fb1cdf8abc6e08e8a9b8c09',
            '74b6c7ef463fd636a0a18975d549faf41513c345c0308f6a5d26d90a01bea5c1',
            'e828effd82ef64e1b29298b6e018b0fe8801f49bcc15f4878364a733581822cc',
            '86f00df1681137c2062a53a9c94e2649697067b918bb5e86d178b05ff3e88d65',
            '3f07ced3ced89ee1786050056e477957da209610169c9cb65190841560c7585c'
        )) <> 5 then
        raise exception 'native Moutai normalized-fact seed is incomplete';
    end if;
end $$;

insert into audit.data_snapshots (
    as_of_at,cutoff_policy_version,manifest,snapshot_hash
) values (
    '2021-08-30 15:00:00+08',
    'pit_cutoff_v1',
    jsonb_build_object(
        'scope','native_moutai_2021_phase_a_v4_frozen_manifest',
        'issuer_code','KWEICHOW_MOUTAI',
        'security_code','600519.SH',
        'decision_cutoff','2021-08-30T15:00:00+08:00',
        'eligible_rule','available_at <= decision_cutoff',
        'cutoff_policy_version','pit_cutoff_v1',
        'financial_fact_count',13,
        'financial_fact_hashes',jsonb_build_array(
            '1a5f723fe27e086f3a5dc7c44f2d07a920dc3e9e65af87b430b00c9ad896b509',
            '1337b52e09f127c4f86281714a28c7e8dd04a8abb21a8e1f807d1d51bb786ffa',
            'd42d6071c2df12bb975c7f72c8acc861f2bfea06c89614e3a0579324234270d9',
            '40e3bc475f7166c29d7f5d10d4f4e259ee1a5bdf8b474dba870c003770a3d5b1',
            'd5b05f66d74be87e35b8ad7e13fc6a18b3552db014a71a0cc14ae352793322ea',
            '0ab47ad9dd4b4b5153f5cbcadefbfeaf010295dbf8b2af8104465f1938a11e20',
            '82526a93a218d4d5bcbd2e20eda762c939f04d333bd283c4d9cf278d23a78f54',
            '0d3dd3232a86b6a90cd9527bdc7d73220e85a053afc3021930def793e1628d48',
            '5330df5e8985745b73bf7f280071e353a1a39e0be8f0cb4912a19a4aaaf4582d',
            '14dd3ac9b283fe85690d087578a5008aad063be86aa360a9c998965ba26e8c6a',
            '406a83c52b588c9649f3b806f9082c344629c30cd50eea2a7f5153b032f1afd5',
            '189ed7402ee994aec87a21db5dafdb848c00f3acf4d093f26e3f49a4bb2cf337',
            '53753b17a1781bd01d2fbb60113ceb1aa2197fbf89d51afeb6ffa53a2e6fda3d'
        ),
        'normalized_fact_count',5,
        'normalized_fact_hashes',jsonb_build_array(
            'b8c43d080c52ee00cb9ae19f9788d9ca8359e4507fb1cdf8abc6e08e8a9b8c09',
            '74b6c7ef463fd636a0a18975d549faf41513c345c0308f6a5d26d90a01bea5c1',
            'e828effd82ef64e1b29298b6e018b0fe8801f49bcc15f4878364a733581822cc',
            '86f00df1681137c2062a53a9c94e2649697067b918bb5e86d178b05ff3e88d65',
            '3f07ced3ced89ee1786050056e477957da209610169c9cb65190841560c7585c'
        ),
        'source_document_count',3,
        'source_document_fingerprints',jsonb_build_array(
            'source_url:https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2021-03-31/600519_20210331_1.pdf',
            '8527c8faba38d77c8ecdc13a4e567b9424940440790528921a93f43a16f06011',
            '709543434cc77e94aeb9a01a48a02bd8335fb016f04436f0ac6bc18bf0a11d71'
        ),
        'market_bar_hash','d8e3c33cfa5aabf5727ebc0a4ed93763e34041d5f4833c6af11c650c0bed1bf8',
        'market_close',1586.0,
        'market_available_at','2021-08-30T15:00:00+08:00',
        'data_quality','provisional',
        'hash_policies',jsonb_build_array(
            'pit_financial_fact_v1','normalized_fact_explicit_v1',
            'stable_document_fingerprint_v1','frozen_manifest_sha256_v1'
        )
    ),
    '68a8590234c749dcf272a156d1afc74cebea9dc78e5e686ca0bc88eb2915f027'
)
on conflict (snapshot_hash) do nothing;

insert into model.model_versions (
    model_name,semantic_version,model_family,status,git_commit_sha,config_hash,
    effective_from,notes
) values (
    'moutai_owner_earnings_native','1.0.0','owner_earnings_dcf','validated',
    '87f32ab7c342f5648b1e72741458e4962baa53a2',
    '8e2a16293534ea8a5ede0d6d1de90831e0b6aa9c963b0661fb1eb7ea703dc242',
    '2026-08-30 18:55:00+08',
    'Native V1.2 Moutai replay; code validated, source data provisional.'
)
on conflict (model_name,semantic_version) do update set
    model_family=excluded.model_family,
    status=excluded.status,
    git_commit_sha=excluded.git_commit_sha,
    config_hash=excluded.config_hash,
    effective_from=excluded.effective_from,
    notes=excluded.notes;

insert into model.valuation_runs (
    issuer_id,security_id,as_of_at,snapshot_id,model_version_id,
    scenario_set_version,status,started_at,completed_at,input_hash,output_hash
)
select i.issuer_id,s.security_id,'2021-08-30 15:00:00+08',ds.snapshot_id,
       mv.model_version_id,'consumer_scenario_policy_v1','succeeded',now(),now(),
       '73e174fa57695eeaf2f36a12eeab7afaa85ac7d31927c0f155145e29becaaf89',
       '98817cf2e591fa075812bf84984aad29ccc32dbca7af62d73515ca1a14be4bd3'
from master.issuers i
join master.securities s on s.issuer_id=i.issuer_id and s.security_code='600519.SH'
join audit.data_snapshots ds on ds.snapshot_hash='68a8590234c749dcf272a156d1afc74cebea9dc78e5e686ca0bc88eb2915f027'
join model.model_versions mv on mv.model_name='moutai_owner_earnings_native' and mv.semantic_version='1.0.0'
where i.issuer_code='KWEICHOW_MOUTAI'
  and not exists (
      select 1 from model.valuation_runs vr
      where vr.input_hash='73e174fa57695eeaf2f36a12eeab7afaa85ac7d31927c0f155145e29becaaf89'
  );

-- Existing environments may already have the run but on an older snapshot version.
update model.valuation_runs
set snapshot_id=(select snapshot_id from audit.data_snapshots
                 where snapshot_hash='68a8590234c749dcf272a156d1afc74cebea9dc78e5e686ca0bc88eb2915f027')
where input_hash='73e174fa57695eeaf2f36a12eeab7afaa85ac7d31927c0f155145e29becaaf89';

with run as (
    select run_id from model.valuation_runs
    where input_hash='73e174fa57695eeaf2f36a12eeab7afaa85ac7d31927c0f155145e29becaaf89'
    order by created_at limit 1
), rows(scenario,assumption_key,value_numeric,value_text,unit,source_kind,provenance) as (
    values
    ('common','current_price',1586.0,null,'CNY/share','market_fact','{"record_hash":"d8e3c33cfa5aabf5727ebc0a4ed93763e34041d5f4833c6af11c650c0bed1bf8"}'::jsonb),
    ('common','investment_hurdle',0.15,null,'ratio','investment_policy','{"policy":"five_year_15pct_hurdle_v1"}'::jsonb),
    ('common','maintenance_reserve_factor',0.95,null,'ratio','normalization_policy','{"rule_version":"moutai_owner_earnings_normalization_v1"}'::jsonb),
    ('common','normalized_owner_earnings_per_share',38.5177842,null,'CNY/share','normalized_fact','{"record_hash":"3f07ced3ced89ee1786050056e477957da209610169c9cb65190841560c7585c"}'::jsonb),
    ('common','growth_anchor',0.1038,null,'ratio','normalized_fact','{"record_hash":"86f00df1681137c2062a53a9c94e2649697067b918bb5e86d178b05ff3e88d65"}'::jsonb),
    ('common','normalization_version',null,'moutai_owner_earnings_normalization_v1',null,'model_policy','{}'::jsonb),
    ('common','scenario_policy_version',null,'consumer_scenario_policy_v1',null,'model_policy','{}'::jsonb),
    ('common','data_quality',null,'provisional',null,'quality_gate','{"automatic_allocation_eligible":false}'::jsonb),
    ('pessimistic','starting_owner_earnings_per_share',38.5177842,null,'CNY/share','normalized_fact','{}'::jsonb),
    ('pessimistic','first_five_year_growth',0.0638,null,'ratio','scenario_policy','{"formula":"max(0, growth_anchor - 0.04)"}'::jsonb),
    ('pessimistic','discount_rate',0.105,null,'ratio','scenario_policy','{}'::jsonb),
    ('pessimistic','perpetual_growth',0.020,null,'ratio','scenario_policy','{}'::jsonb),
    ('pessimistic','explicit_years',15,null,'years','scenario_policy','{}'::jsonb),
    ('pessimistic','fade_start_year',4,null,'year','scenario_policy','{}'::jsonb),
    ('base','starting_owner_earnings_per_share',38.5177842,null,'CNY/share','normalized_fact','{}'::jsonb),
    ('base','first_five_year_growth',0.1038,null,'ratio','scenario_policy','{"formula":"growth_anchor"}'::jsonb),
    ('base','discount_rate',0.095,null,'ratio','scenario_policy','{}'::jsonb),
    ('base','perpetual_growth',0.025,null,'ratio','scenario_policy','{}'::jsonb),
    ('base','explicit_years',15,null,'years','scenario_policy','{}'::jsonb),
    ('base','fade_start_year',4,null,'year','scenario_policy','{}'::jsonb),
    ('optimistic','starting_owner_earnings_per_share',38.5177842,null,'CNY/share','normalized_fact','{}'::jsonb),
    ('optimistic','first_five_year_growth',0.1338,null,'ratio','scenario_policy','{"formula":"min(0.15, growth_anchor + 0.03)"}'::jsonb),
    ('optimistic','discount_rate',0.085,null,'ratio','scenario_policy','{}'::jsonb),
    ('optimistic','perpetual_growth',0.030,null,'ratio','scenario_policy','{}'::jsonb),
    ('optimistic','explicit_years',15,null,'years','scenario_policy','{}'::jsonb),
    ('optimistic','fade_start_year',4,null,'year','scenario_policy','{}'::jsonb)
)
insert into model.run_assumptions (
    run_id,scenario,assumption_key,value_numeric,value_text,unit,source_kind,provenance
)
select run.run_id,rows.scenario,rows.assumption_key,rows.value_numeric,
       rows.value_text,rows.unit,rows.source_kind,rows.provenance
from run cross join rows
on conflict (run_id,scenario,assumption_key) do update set
    value_numeric=excluded.value_numeric,
    value_text=excluded.value_text,
    unit=excluded.unit,
    source_kind=excluded.source_kind,
    provenance=excluded.provenance;

with run as (
    select run_id from model.valuation_runs
    where input_hash='73e174fa57695eeaf2f36a12eeab7afaa85ac7d31927c0f155145e29becaaf89'
    order by created_at limit 1
), rows(scenario,output_key,value_numeric,value_text,unit,metadata) as (
    values
    ('pessimistic','intrinsic_value_per_share',603.0677888177593,null,'CNY/share','{}'::jsonb),
    ('pessimistic','five_year_irr',-0.15658568617388613,null,'ratio','{}'::jsonb),
    ('pessimistic','target_buy_price_15pct',477.63235028039274,null,'CNY/share','{}'::jsonb),
    ('pessimistic','terminal_value_share',0.525584711179353,null,'ratio','{"warning_threshold":0.60}'::jsonb),
    ('pessimistic','year_five_value_per_share',646.8610210012225,null,'CNY/share','{}'::jsonb),
    ('base','intrinsic_value_per_share',930.5299864767308,null,'CNY/share','{}'::jsonb),
    ('base','five_year_irr',-0.023967490793221462,null,'ratio','{}'::jsonb),
    ('base','target_buy_price_15pct',744.4695241484767,null,'CNY/share','{}'::jsonb),
    ('base','terminal_value_share',0.46385655645318347,null,'ratio','{"warning_threshold":0.60}'::jsonb),
    ('base','year_five_value_per_share',1080.8361411492857,null,'CNY/share','{}'::jsonb),
    ('base','legacy_base_value',1433.46,null,'CNY/share','{"source":"LEGACY_BACKTEST_XLSX"}'::jsonb),
    ('base','native_minus_legacy_base',-502.9300135232692,null,'CNY/share','{"interpretation":"reconciliation_gap_not_model_error"}'::jsonb),
    ('optimistic','intrinsic_value_per_share',1435.342514370947,null,'CNY/share','{}'::jsonb),
    ('optimistic','five_year_irr',0.06204820355188434,null,'ratio','{}'::jsonb),
    ('optimistic','target_buy_price_15pct',1172.965016257291,null,'CNY/share','{}'::jsonb),
    ('optimistic','terminal_value_share',0.39318218994313725,null,'ratio','{"warning_threshold":0.60}'::jsonb),
    ('optimistic','year_five_value_per_share',1781.2084136738257,null,'CNY/share','{}'::jsonb),
    ('decision','signal',null,'avoid_at_price',null,'{"hurdle":0.15,"data_quality":"provisional"}'::jsonb)
)
insert into model.valuation_outputs (
    run_id,scenario,output_key,value_numeric,value_text,unit,metadata
)
select run.run_id,rows.scenario,rows.output_key,rows.value_numeric,
       rows.value_text,rows.unit,rows.metadata
from run cross join rows
on conflict (run_id,scenario,output_key) do update set
    value_numeric=excluded.value_numeric,
    value_text=excluded.value_text,
    unit=excluded.unit,
    metadata=excluded.metadata;

with run as (
    select run_id from model.valuation_runs
    where input_hash='73e174fa57695eeaf2f36a12eeab7afaa85ac7d31927c0f155145e29becaaf89'
    order by created_at limit 1
)
insert into model.reverse_dcf_results (
    run_id,target_price,solved_variable,solution_value,lower_bound,upper_bound,
    residual,iterations,converged,diagnostics
)
select run_id,1586.0,'first_five_year_growth',0.1878917407584595,
       -0.5,0.5,8.398956197197549e-09,40,true,
       '{"shared_forward_model":true,"discount_rate":0.095,"perpetual_growth":0.025,"explicit_years":15,"fade_start_year":4}'::jsonb
from run
where not exists (
    select 1 from model.reverse_dcf_results r
    where r.run_id=run.run_id and r.target_price=1586.0
      and r.solved_variable='first_five_year_growth'
);

commit;
