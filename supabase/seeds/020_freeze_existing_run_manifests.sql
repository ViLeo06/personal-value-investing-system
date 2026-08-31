begin;

with valuation_payloads as (
    select
        vr.run_id,
        jsonb_build_object(
            'run_type','valuation',
            'run_id',vr.run_id,
            'issuer_code',i.issuer_code,
            'security_code',s.security_code,
            'as_of_at',vr.as_of_at,
            'snapshot_id',vr.snapshot_id,
            'snapshot_hash',ds.snapshot_hash,
            'snapshot_policy_version',ds.cutoff_policy_version,
            'model_version_id',vr.model_version_id,
            'model_name',mv.model_name,
            'model_family',mv.model_family,
            'semantic_version',mv.semantic_version,
            'model_git_commit_sha',mv.git_commit_sha,
            'model_config_hash',mv.config_hash,
            'scenario_set_version',vr.scenario_set_version,
            'status',vr.status,
            'input_hash',vr.input_hash,
            'output_hash',vr.output_hash,
            'started_at',vr.started_at,
            'completed_at',vr.completed_at,
            'assumptions',coalesce((
                select jsonb_agg(
                    jsonb_build_object(
                        'scenario',a.scenario,
                        'assumption_key',a.assumption_key,
                        'value_numeric',a.value_numeric,
                        'value_text',a.value_text,
                        'value_json',a.value_json,
                        'unit',a.unit,
                        'source_kind',a.source_kind,
                        'provenance',a.provenance
                    ) order by a.scenario,a.assumption_key,a.assumption_id
                )
                from model.run_assumptions a
                where a.run_id=vr.run_id
            ),'[]'::jsonb),
            'lineage',coalesce((
                select jsonb_agg(
                    jsonb_build_object(
                        'input_type',rl.input_type,
                        'input_id',rl.input_id,
                        'input_hash',rl.input_hash,
                        'metadata',rl.metadata
                    ) order by rl.input_type,rl.input_id,rl.lineage_id
                )
                from audit.run_lineage rl
                where rl.run_type like 'valuation%'
                  and rl.run_id=vr.run_id
            ),'[]'::jsonb)
        ) as manifest
    from model.valuation_runs vr
    join master.issuers i on i.issuer_id=vr.issuer_id
    left join master.securities s on s.security_id=vr.security_id
    join audit.data_snapshots ds on ds.snapshot_id=vr.snapshot_id
    join model.model_versions mv on mv.model_version_id=vr.model_version_id
    where vr.run_id in (
        '8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,
        '40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid
    )
), hashed as (
    select run_id,manifest,
           encode(extensions.digest(convert_to(manifest::text,'UTF8'),'sha256'),'hex') as manifest_hash
    from valuation_payloads
)
insert into audit.run_manifests
    (run_type,run_id,manifest,manifest_hash,notes)
select
    'valuation',h.run_id,h.manifest,h.manifest_hash,
    case when h.run_id='8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
         then 'Formal Gate 0 run; intentionally blocked until evidence and inputs pass.'
         else 'Engineering proxy run; never an investment conclusion.' end
from hashed h
on conflict (run_type,run_id,manifest_hash) do nothing;

with backtest_payload as (
    select
        b.backtest_run_id as run_id,
        jsonb_build_object(
            'run_type','backtest',
            'backtest_run_id',b.backtest_run_id,
            'universe_id',b.universe_id,
            'universe_code',u.universe_code,
            'universe_policy_version',u.construction_policy_version,
            'model_version_id',b.model_version_id,
            'model_name',mv.model_name,
            'model_family',mv.model_family,
            'semantic_version',mv.semantic_version,
            'start_date',b.start_date,
            'end_date',b.end_date,
            'holding_horizon_months',b.holding_horizon_months,
            'configuration',b.configuration,
            'git_commit_sha',b.git_commit_sha,
            'status',b.status,
            'started_at',b.started_at,
            'completed_at',b.completed_at,
            'result_hash',b.result_hash,
            'decisions',coalesce((
                select jsonb_agg(
                    jsonb_build_object(
                        'decision_id',d.decision_id,
                        'decision_at',d.decision_at,
                        'issuer_id',d.issuer_id,
                        'security_id',d.security_id,
                        'valuation_run_id',d.valuation_run_id,
                        'signal',d.signal,
                        'target_weight',d.target_weight,
                        'decision_payload',d.decision_payload,
                        'frozen_at',d.frozen_at
                    ) order by d.decision_at,d.decision_id
                )
                from backtest.decision_events d
                where d.backtest_run_id=b.backtest_run_id
            ),'[]'::jsonb),
            'transactions',coalesce((
                select jsonb_agg(
                    jsonb_build_object(
                        'transaction_id',t.transaction_id,
                        'decision_id',t.decision_id,
                        'security_id',t.security_id,
                        'trade_date',t.trade_date,
                        'side',t.side,
                        'quantity',t.quantity,
                        'price',t.price,
                        'fees',t.fees,
                        'slippage',t.slippage,
                        'currency',t.currency
                    ) order by t.trade_date,t.transaction_id
                )
                from backtest.transactions t
                where t.backtest_run_id=b.backtest_run_id
            ),'[]'::jsonb),
            'performance_metrics',coalesce((
                select jsonb_agg(
                    jsonb_build_object(
                        'metric_code',p.metric_code,
                        'value_numeric',p.value_numeric,
                        'value_text',p.value_text,
                        'unit',p.unit,
                        'metadata',p.metadata
                    ) order by p.metric_code
                )
                from backtest.performance_metrics p
                where p.backtest_run_id=b.backtest_run_id
            ),'[]'::jsonb),
            'lineage',coalesce((
                select jsonb_agg(
                    jsonb_build_object(
                        'input_type',rl.input_type,
                        'input_id',rl.input_id,
                        'input_hash',rl.input_hash,
                        'metadata',rl.metadata
                    ) order by rl.input_type,rl.input_id,rl.lineage_id
                )
                from audit.run_lineage rl
                where rl.run_type='backtest_proxy'
                  and rl.run_id=b.backtest_run_id
            ),'[]'::jsonb)
        ) as manifest
    from backtest.backtest_runs b
    join backtest.universes u on u.universe_id=b.universe_id
    join model.model_versions mv on mv.model_version_id=b.model_version_id
    where b.backtest_run_id='bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
), hashed as (
    select run_id,manifest,
           encode(extensions.digest(convert_to(manifest::text,'UTF8'),'sha256'),'hex') as manifest_hash
    from backtest_payload
)
insert into audit.run_manifests
    (run_type,run_id,manifest,manifest_hash,notes)
select
    'backtest',run_id,manifest,manifest_hash,
    'Five-year engineering proxy; market data and corporate actions still require formal evidence reconciliation.'
from hashed
on conflict (run_type,run_id,manifest_hash) do nothing;

commit;
