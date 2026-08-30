-- These queries must return zero rows in a valid Gate-0 database.

-- Financial evidence is frozen separately from the full Phase-A inputs.
select snapshot_id,snapshot_kind,is_frozen,manifest
from audit.data_snapshots
where snapshot_hash='9950df576f62d3a87aac8b7ee276a173'
  and not (snapshot_kind='financial_evidence' and is_frozen
           and (manifest->>'snapshot_item_count')::int=7);

select snapshot_id,snapshot_kind,is_frozen,manifest
from audit.data_snapshots
where snapshot_hash=md5('KWEICHOW_MOUTAI|600519.SH|2021-04-01T00:00:00+08:00|phase_a_full|v1')
  and not (snapshot_kind='phase_a_full' and is_frozen
           and (manifest->>'snapshot_item_count')::int=8
           and parent_snapshot_id is not null);

-- The valuation run must use the complete Phase-A snapshot, not the smaller
-- financial-only parent.
select vr.run_id,ds.snapshot_kind
from model.valuation_runs vr
join master.issuers i on i.issuer_id=vr.issuer_id
join audit.data_snapshots ds on ds.snapshot_id=vr.snapshot_id
where i.issuer_code='KWEICHOW_MOUTAI'
  and vr.scenario_set_version='moutai_gate0_scenarios_v1'
  and ds.snapshot_kind<>'phase_a_full';

-- A frozen full snapshot must contain one market target and inherit exactly
-- seven financial/evidence members.
select ds.snapshot_id,
       count(*) filter(where si.input_type='pit.market_bars') as market_rows,
       count(*) filter(where si.input_type<>'pit.market_bars') as inherited_rows
from audit.data_snapshots ds
join audit.snapshot_items si using(snapshot_id)
where ds.snapshot_kind='phase_a_full'
  and ds.snapshot_hash=md5('KWEICHOW_MOUTAI|600519.SH|2021-04-01T00:00:00+08:00|phase_a_full|v1')
group by ds.snapshot_id
having count(*) filter(where si.input_type='pit.market_bars')<>1
    or count(*) filter(where si.input_type<>'pit.market_bars')<>7;
