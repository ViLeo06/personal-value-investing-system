begin;

with target_security as (
    select security_id
    from master.securities
    where security_code = '600519.SH'
), reference_bar as (
    select m.*, s.source_code
    from target_security t
    cross join lateral pit.market_bars_as_of(
        t.security_id,
        '2021-03-31T16:00:00Z'::timestamptz,
        null,
        '2021-03-31'::date
    ) m
    join raw.data_sources s on s.source_id = m.source_id
    order by m.trade_date desc
    limit 1
), execution_bar as (
    select m.*, s.source_code
    from target_security t
    join pit.market_bars m on m.security_id = t.security_id
    join raw.data_sources s on s.source_id = m.source_id
    cross join reference_bar r
    where m.trade_date > r.trade_date
      and m.open_price is not null
    order by m.trade_date asc, s.priority asc, m.available_at desc
    limit 1
), values_to_insert as (
    select
        'reference_close_price'::text as assumption_key,
        r.close_price as value_numeric,
        'CNY/share'::text as unit,
        jsonb_build_object(
            'bar_id', r.bar_id,
            'trade_date', r.trade_date,
            'available_at', r.available_at,
            'source_code', r.source_code,
            'record_hash', r.record_hash,
            'timing_role', 'decision_reference',
            'methodology_quality', 'derived_requires_reconciliation'
        ) as provenance
    from reference_bar r
    union all
    select
        'execution_open_price',
        e.open_price,
        'CNY/share',
        jsonb_build_object(
            'bar_id', e.bar_id,
            'trade_date', e.trade_date,
            'available_at', e.available_at,
            'source_code', e.source_code,
            'record_hash', e.record_hash,
            'timing_role', 'execution_outcome',
            'methodology_quality', 'derived_requires_reconciliation'
        )
    from execution_bar e
)
insert into model.run_assumptions
    (run_id, scenario, assumption_key, value_numeric, unit, source_kind, provenance)
select
    '8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid,
    'control',
    v.assumption_key,
    v.value_numeric,
    v.unit,
    'market_data',
    v.provenance
from values_to_insert v
where not exists (
    select 1
    from model.run_assumptions a
    where a.run_id = '8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
      and a.scenario = 'control'
      and a.assumption_key = v.assumption_key
);

with present as (
    select count(*) = 2 as complete
    from model.run_assumptions
    where run_id = '8bcbb9d3-7fdb-529a-9f9a-547043040e13'::uuid
      and scenario = 'control'
      and assumption_key in ('reference_close_price','execution_open_price')
), cleaned as (
    select q.issue_id,
           coalesce(
               (
                   select jsonb_agg(item order by ordinality)
                   from jsonb_array_elements(q.details->'missing') with ordinality as x(item, ordinality)
                   where item #>> '{}' not in ('reference_close_price','execution_open_price')
               ),
               '[]'::jsonb
           ) as remaining
    from audit.data_quality_issues q
    cross join present p
    where p.complete
      and q.record_key = 'KWEICHOW_MOUTAI|2021-04-01'
      and q.rule_code = 'GATE0_REQUIRED_INPUT_MISSING'
      and q.status = 'open'
)
update audit.data_quality_issues q
set details = jsonb_set(
        q.details || jsonb_build_object(
            'market_price_status', 'loaded_derived_pending_reconciliation'
        ),
        '{missing}',
        cleaned.remaining,
        true
    )
from cleaned
where q.issue_id = cleaned.issue_id;

insert into audit.data_quality_issues
    (severity, domain, table_name, record_key, rule_code, description, status, details)
select
    'warning',
    'market_data',
    'pit.market_bars',
    '600519.SH|2021-03-31|2021-04-01',
    'MARKET_PRICE_SECOND_SOURCE_REQUIRED',
    'Decision reference close and execution open are loaded from a derived free source and require independent reconciliation before formal Gate 0 completion.',
    'open',
    jsonb_build_object(
        'security_code', '600519.SH',
        'reference_trade_date', r.trade_date,
        'reference_close', r.close_price,
        'execution_trade_date', e.trade_date,
        'execution_open', e.open_price,
        'source_code', r.source_code,
        'methodology_quality', 'derived_requires_reconciliation'
    )
from reference_bar r
cross join execution_bar e
where not exists (
    select 1
    from audit.data_quality_issues existing
    where existing.rule_code = 'MARKET_PRICE_SECOND_SOURCE_REQUIRED'
      and existing.record_key = '600519.SH|2021-03-31|2021-04-01'
      and existing.status = 'open'
);

commit;
