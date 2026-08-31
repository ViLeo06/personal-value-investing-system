begin;

with target as (
    select issuer_id
    from master.issuers
    where issuer_code = 'KWEICHOW_MOUTAI'
), generated as (
    select m.manifest, m.snapshot_hash
    from target t
    cross join lateral audit.financial_snapshot_manifest(
        t.issuer_id,
        '2021-03-31T16:00:00Z'::timestamptz,
        'pit_cutoff_v3_content_hash'
    ) m
)
insert into audit.data_snapshots
    (as_of_at, cutoff_policy_version, manifest, snapshot_hash)
select
    '2021-03-31T16:00:00Z'::timestamptz,
    'pit_cutoff_v3_content_hash',
    generated.manifest,
    generated.snapshot_hash
from generated
where not exists (
    select 1
    from audit.data_snapshots existing
    where existing.snapshot_hash = generated.snapshot_hash
);

with canonical as (
    select snapshot_id, snapshot_hash
    from audit.data_snapshots
    where cutoff_policy_version = 'pit_cutoff_v3_content_hash'
      and as_of_at = '2021-03-31T16:00:00Z'::timestamptz
    order by created_at desc
    limit 1
)
update model.valuation_runs vr
set snapshot_id = canonical.snapshot_id,
    input_hash = case
        when vr.run_id = '40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid then
            encode(
                extensions.digest(
                    convert_to(
                        canonical.snapshot_hash || '|ocf_proxy|ni_eps_shares|zero_net_cash',
                        'UTF8'
                    ),
                    'sha256'
                ),
                'hex'
            )
        else canonical.snapshot_hash
    end
from canonical
where vr.run_id in (
    '8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,
    '40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid
);

with canonical as (
    select snapshot_id, snapshot_hash
    from audit.data_snapshots
    where cutoff_policy_version = 'pit_cutoff_v3_content_hash'
      and as_of_at = '2021-03-31T16:00:00Z'::timestamptz
    order by created_at desc
    limit 1
)
update audit.run_lineage rl
set input_id = canonical.snapshot_id::text,
    input_hash = case
        when rl.run_id = '40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid then
            encode(
                extensions.digest(
                    convert_to(
                        canonical.snapshot_hash || '|ocf_proxy|ni_eps_shares|zero_net_cash',
                        'UTF8'
                    ),
                    'sha256'
                ),
                'hex'
            )
        else canonical.snapshot_hash
    end,
    metadata = rl.metadata || jsonb_build_object(
        'snapshot_policy_version', 'pit_cutoff_v3_content_hash',
        'snapshot_hash', canonical.snapshot_hash
    )
from canonical
where rl.run_id in (
    '8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,
    '40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid
)
and rl.input_type = 'data_snapshot';

with canonical as (
    select snapshot_hash
    from audit.data_snapshots
    where cutoff_policy_version = 'pit_cutoff_v3_content_hash'
      and as_of_at = '2021-03-31T16:00:00Z'::timestamptz
    order by created_at desc
    limit 1
)
update model.run_assumptions a
set provenance = a.provenance || jsonb_build_object(
    'snapshot_policy_version', 'pit_cutoff_v3_content_hash',
    'snapshot_hash', canonical.snapshot_hash
)
from canonical
where a.run_id in (
    '8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,
    '40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid
);

with canonical as (
    select snapshot_hash
    from audit.data_snapshots
    where cutoff_policy_version = 'pit_cutoff_v3_content_hash'
      and as_of_at = '2021-03-31T16:00:00Z'::timestamptz
    order by created_at desc
    limit 1
)
update audit.data_quality_issues q
set details = q.details || jsonb_build_object(
    'snapshot_policy_version', 'pit_cutoff_v3_content_hash',
    'snapshot_hash', canonical.snapshot_hash
)
from canonical
where q.record_key = 'KWEICHOW_MOUTAI|2021-04-01'
  and q.rule_code = 'GATE0_REQUIRED_INPUT_MISSING'
  and q.status = 'open';

commit;
