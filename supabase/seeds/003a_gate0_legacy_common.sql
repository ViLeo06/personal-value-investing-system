begin;

-- Idempotent Gate-0 legacy migration bridge. Workbook-derived records are not authoritative PIT data.

insert into raw.data_sources (source_code,name,source_type,homepage_url,license_name,is_free,is_open_source,pit_capability,priority,notes)
values ('LEGACY_BACKTEST_XLSX','价值投资估值系统_历史回测_2021-2026_V1.0.xlsx','legacy_workbook',null,'User-owned project artifact',true,false,'derived',90,'Migration bridge and golden-test source; not an authoritative market-data feed.')
on conflict (source_code) do update set notes=excluded.notes;

insert into raw.data_sources (source_code,name,source_type,homepage_url,license_name,is_free,is_open_source,pit_capability,priority,notes)
values ('LEGACY_V11_XLSX','个人价值投资与股票估值系统_V1.1.xlsx','legacy_workbook',null,'User-owned project artifact',true,false,'derived',90,'Golden-test source for current-model formulas.')
on conflict (source_code) do update set notes=excluded.notes;

insert into raw.documents (source_id,document_type,title,storage_uri,mime_type,language,published_at,effective_date,content_hash,parser_version,metadata)
select source_id,'model_workbook','价值投资估值系统_历史回测_2021-2026_V1.0.xlsx','project-artifact://handoff/价值投资估值系统_历史回测_2021-2026_V1.0.xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','zh-CN','2026-08-30T00:00:00+08:00'::timestamptz,'2026-08-30'::date,'ec4cc507acfa6e73427172cc0e3011881c96e7b7727bfe7226e15ab6b5665e6e','openpyxl-extract-v1','{"phase_a_date":"2021-08-30","phase_b_date":"2026-08-28","role":"legacy_frozen_replay"}'::jsonb from raw.data_sources where source_code='LEGACY_BACKTEST_XLSX' on conflict do nothing;

insert into raw.documents (source_id,document_type,title,storage_uri,mime_type,language,published_at,effective_date,content_hash,parser_version,metadata)
select source_id,'model_workbook','个人价值投资与股票估值系统_V1.1.xlsx','project-artifact://handoff/个人价值投资与股票估值系统_V1.1.xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','zh-CN','2026-08-30T00:00:00+08:00'::timestamptz,'2026-08-30'::date,'c8f7f8ec1fb6240e40a66c3fad97adfa52e4b5aa368abcab9aef0737b0fabd44','openpyxl-extract-v1','{"role":"v1_1_formula_golden"}'::jsonb from raw.data_sources where source_code='LEGACY_V11_XLSX' on conflict do nothing;

insert into fundamentals.metric_definitions (metric_code,name_cn,name_en,statement_type,default_unit,description) values ('owner_earnings_per_share','所有者收益/股','Owner earnings per share','valuation_input','currency/share','Normalized cash earnings attributable to one share.') on conflict (metric_code) do update set name_cn=excluded.name_cn,name_en=excluded.name_en,statement_type=excluded.statement_type,default_unit=excluded.default_unit,description=excluded.description;

insert into fundamentals.metric_definitions (metric_code,name_cn,name_en,statement_type,default_unit,description) values ('intrinsic_value_per_share','内在价值/股','Intrinsic value per share','valuation_output','currency/share','Scenario intrinsic value per share.') on conflict (metric_code) do update set name_cn=excluded.name_cn,name_en=excluded.name_en,statement_type=excluded.statement_type,default_unit=excluded.default_unit,description=excluded.description;

insert into fundamentals.metric_definitions (metric_code,name_cn,name_en,statement_type,default_unit,description) values ('predicted_5y_irr','预测5年年化收益','Predicted five-year IRR','valuation_output','ratio','Model-predicted five-year economic IRR.') on conflict (metric_code) do update set name_cn=excluded.name_cn,name_en=excluded.name_en,statement_type=excluded.statement_type,default_unit=excluded.default_unit,description=excluded.description;

insert into fundamentals.metric_definitions (metric_code,name_cn,name_en,statement_type,default_unit,description) values ('target_buy_price_15pct','15%目标买入价','15% target buy price','valuation_output','currency/share','Maximum price consistent with a 15% target annual return.') on conflict (metric_code) do update set name_cn=excluded.name_cn,name_en=excluded.name_en,statement_type=excluded.statement_type,default_unit=excluded.default_unit,description=excluded.description;

insert into fundamentals.metric_definitions (metric_code,name_cn,name_en,statement_type,default_unit,description) values ('realized_tsr','实际股东总回报','Realized total shareholder return','backtest_output','ratio','Corporate-action-aware total shareholder return.') on conflict (metric_code) do update set name_cn=excluded.name_cn,name_en=excluded.name_en,statement_type=excluded.statement_type,default_unit=excluded.default_unit,description=excluded.description;

insert into fundamentals.metric_definitions (metric_code,name_cn,name_en,statement_type,default_unit,description) values ('realized_tsr_cagr','实际TSR年化','Realized TSR CAGR','backtest_output','ratio','Annualized total shareholder return over the evaluation horizon.') on conflict (metric_code) do update set name_cn=excluded.name_cn,name_en=excluded.name_en,statement_type=excluded.statement_type,default_unit=excluded.default_unit,description=excluded.description;

insert into audit.data_snapshots (as_of_at,cutoff_policy_version,manifest,snapshot_hash)
values ('2021-08-30T16:00:00+08:00'::timestamptz,'pit_cutoff_v1','{"companies":["KWEICHOW_MOUTAI","TENCENT","BYD","CMB"],"decision_date":"2021-08-30","eligible_rule":"available_at <= decision_at","information_cutoff_policy":"market_close_by_exchange","limitations":["legacy workbook stores frozen outputs but not full parameter sets","some corporate-action reinvestment prices are proxies","BYD/CMB source cells contained post-cutoff links; those links are excluded"],"scope":"gate0_legacy_frozen_replay","source_document_sha256":"ec4cc507acfa6e73427172cc0e3011881c96e7b7727bfe7226e15ab6b5665e6e"}'::jsonb,'d8c8fac03a4fbbb22227f67eed397f2c9c1051ba8488123c2d328464b0f94df8') on conflict (snapshot_hash) do nothing;

insert into model.model_versions (model_name,semantic_version,model_family,status,config_hash,effective_from,notes) values ('legacy_owner_earnings_dcf','1.0.0','owner_earnings_dcf','frozen','c9dc04480f9b9b812a295298d369e9d7bdb263358b759fd2ae7fd1334aeb4c9d','2021-08-30T00:00:00+08:00'::timestamptz,'Frozen output bridge from V1.0 historical replay workbook; full legacy parameter set is unavailable.') on conflict (model_name,semantic_version) do update set status='frozen',notes=excluded.notes;

insert into model.model_versions (model_name,semantic_version,model_family,status,config_hash,effective_from,notes) values ('legacy_core_fcf_sotp','1.0.0','fcff_sotp','frozen','91957870713e4fbf114cbd28b49af14525680d44f0ba5cacdf96bd9f0356e13a','2021-08-30T00:00:00+08:00'::timestamptz,'Frozen output bridge from V1.0 historical replay workbook; full legacy parameter set is unavailable.') on conflict (model_name,semantic_version) do update set status='frozen',notes=excluded.notes;

insert into model.model_versions (model_name,semantic_version,model_family,status,config_hash,effective_from,notes) values ('legacy_value_driver_fcff','1.0.0','value_driver_fcff','frozen','595a6f8b0b25cb16c7194de620e889d690416e050fefe5b3f42f3340a9407c95','2021-08-30T00:00:00+08:00'::timestamptz,'Frozen output bridge from V1.0 historical replay workbook; full legacy parameter set is unavailable.') on conflict (model_name,semantic_version) do update set status='frozen',notes=excluded.notes;

insert into model.model_versions (model_name,semantic_version,model_family,status,config_hash,effective_from,notes) values ('legacy_residual_income','1.0.0','residual_income','frozen','dfe6213aafd536fd5c6b85530c7d7557d63a4b5176cdba5381e86fb7ab44016c','2021-08-30T00:00:00+08:00'::timestamptz,'Frozen output bridge from V1.0 historical replay workbook; full legacy parameter set is unavailable.') on conflict (model_name,semantic_version) do update set status='frozen',notes=excluded.notes;

insert into backtest.universes (universe_code,name,description,construction_policy_version)
values ('GATE0_LEGACY_4','Gate 0 legacy four-company validation set','Manually selected four-company architecture-validation set; not a representative investment universe.','legacy_manual_v1') on conflict (universe_code) do update set description=excluded.description;

insert into backtest.backtest_runs (universe_id,model_version_id,start_date,end_date,holding_horizon_months,configuration,git_commit_sha,status,started_at,completed_at,result_hash) select u.universe_id,mv.model_version_id,'2021-08-30'::date,'2026-08-28'::date,60,'{"corporate_action_method":"reinvest_at_legacy_proxy_price","hurdle":0.15,"mode":"information_set_constrained_replay","phase_a_frozen":true}'::jsonb,null,'succeeded',now(),now(),'a76b813d9a2f3fd092a8b84d21ff62109f6e620892cb8f3065004e94f76376f9' from backtest.universes u join model.model_versions mv on mv.model_name='legacy_owner_earnings_dcf' and mv.semantic_version='1.0.0' where u.universe_code='GATE0_LEGACY_4' and not exists (select 1 from backtest.backtest_runs br where br.universe_id=u.universe_id and br.start_date='2021-08-30'::date and br.end_date='2026-08-28'::date);

insert into audit.run_lineage (run_type,run_id,input_type,input_id,input_hash,metadata) select 'backtest',br.backtest_run_id,'legacy_report','gate0_report','a76b813d9a2f3fd092a8b84d21ff62109f6e620892cb8f3065004e94f76376f9','{"formal_strategy_evidence":false,"mode":"legacy_architecture_golden_test"}'::jsonb from backtest.backtest_runs br join backtest.universes u on u.universe_id=br.universe_id where u.universe_code='GATE0_LEGACY_4' and br.start_date='2021-08-30'::date and not exists (select 1 from audit.run_lineage rl where rl.run_type='backtest' and rl.run_id=br.backtest_run_id and rl.input_type='legacy_report' and rl.input_id='gate0_report');

commit;
