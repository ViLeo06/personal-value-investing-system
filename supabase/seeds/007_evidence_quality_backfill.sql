begin;

update raw.documents
set available_at='2021-03-31 00:00:00+08',
    publication_precision='date',
    evidence_quality='official_reference'
where source_url='https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2021-03-31/600519_20210331_1.pdf';

update raw.documents
set available_at='2021-08-02 09:30:00+08',
    publication_precision='minute',
    evidence_quality='derived_archive'
where content_hash in (
    '8527c8faba38d77c8ecdc13a4e567b9424940440790528921a93f43a16f06011',
    '709543434cc77e94aeb9a01a48a02bd8335fb016f04436f0ac6bc18bf0a11d71'
);

update raw.documents
set available_at=published_at,
    publication_precision='minute',
    evidence_quality='proxy'
where content_hash='c7a935619b026f92f45978727d0d1c3535416f25bd667fd6a5b527625a38661a';

with native_outcome as (
    select o.outcome_id,o.start_price,o.end_price,o.final_share_multiplier,
           o.terminal_value,o.total_return,o.annualized_return,
           o.benchmark_annualized_return,o.excess_return,o.outcome_payload
    from backtest.decision_outcomes o
    join backtest.decision_events de on de.decision_id=o.decision_id
    join model.valuation_runs vr on vr.run_id=de.valuation_run_id
    where vr.input_hash='73e174fa57695eeaf2f36a12eeab7afaa85ac7d31927c0f155145e29becaaf89'
)
insert into backtest.outcome_revisions (
    outcome_id,revision_code,is_current,reconciled_at,start_price,end_price,
    final_share_multiplier,terminal_value,total_return,annualized_return,
    benchmark_annualized_return,excess_return,source_quality,
    reconciliation_payload
)
select outcome_id,'legacy_proxy_v1',true,'2026-08-30 18:55:00+08',
       start_price,end_price,final_share_multiplier,terminal_value,total_return,
       annualized_return,benchmark_annualized_return,excess_return,
       'legacy_proxy',outcome_payload ||
       '{"revision_role":"initial_proxy_baseline","replace_with_official_revision":true}'::jsonb
from native_outcome
on conflict (outcome_id,revision_code) do update set
    is_current=excluded.is_current,
    reconciled_at=excluded.reconciled_at,
    start_price=excluded.start_price,
    end_price=excluded.end_price,
    final_share_multiplier=excluded.final_share_multiplier,
    terminal_value=excluded.terminal_value,
    total_return=excluded.total_return,
    annualized_return=excluded.annualized_return,
    benchmark_annualized_return=excluded.benchmark_annualized_return,
    excess_return=excluded.excess_return,
    source_quality=excluded.source_quality,
    reconciliation_payload=excluded.reconciliation_payload;

commit;
