begin;

-- This is an engineering proxy run, not a completed investment valuation.
-- Owner earnings is proxied by operating cash flow, shares are estimated from
-- net income / rounded EPS, and net cash is set to zero. The data-quality gap
-- remains open and the run status is completed_proxy.

insert into model.model_versions
    (model_version_id, model_name, semantic_version, model_family, status,
     config_hash, effective_from, notes)
values
    ('7c0e118a-4424-491f-965a-f60e60d0b111'::uuid,
     'Gate 0 Owner Earnings Proxy',
     '0.1.0-gate0',
     'owner_earnings_dcf',
     'development',
     'moutai-2021-proxy-v1',
     '2026-08-30T00:00:00Z'::timestamptz,
     'Engineering-only proxy: OCF as owner earnings, NI/EPS as shares estimate, zero net cash.')
on conflict do nothing;

with target as (
    select i.issuer_id, s.security_id, ds.snapshot_id
    from master.issuers i
    join master.securities s
      on s.issuer_id = i.issuer_id and s.security_code = '600519.SH'
    join audit.data_snapshots ds
      on ds.snapshot_hash = '9950df576f62d3a87aac8b7ee276a173'
    where i.issuer_code = 'KWEICHOW_MOUTAI'
    limit 1
)
insert into model.valuation_runs
    (run_id, issuer_id, security_id, as_of_at, snapshot_id, model_version_id,
     scenario_set_version, status, started_at, input_hash)
select
    '40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid,
    issuer_id,
    security_id,
    '2021-03-31T16:00:00Z'::timestamptz,
    snapshot_id,
    '7c0e118a-4424-491f-965a-f60e60d0b111'::uuid,
    'gate0-moutai-proxy-v1',
    'running',
    now(),
    md5('9950df576f62d3a87aac8b7ee276a173|ocf_proxy|ni_eps_shares|zero_net_cash')
from target
where not exists (
    select 1 from model.valuation_runs
    where run_id = '40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid
);

insert into model.run_assumptions
    (run_id, scenario, assumption_key, value_numeric, value_text, unit,
     source_kind, provenance)
select
    '40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid,
    v.scenario,
    v.assumption_key,
    v.value_numeric,
    v.value_text,
    v.unit,
    v.source_kind,
    v.provenance
from (values
    ('control','methodology_quality',null,'prototype_only',null,'model_control',jsonb_build_object('warning','not an investment conclusion')),
    ('control','owner_earnings_definition',null,'operating_cash_flow_proxy',null,'derived',jsonb_build_object('reason','maintenance capex bridge not yet source-complete')),
    ('control','shares_definition',null,'net_income_divided_by_rounded_eps',null,'derived',jsonb_build_object('precision','approximate')),
    ('control','net_cash',0.0,null,'CNY','assumption',jsonb_build_object('reason','balance-sheet convention not yet complete')),
    ('bear','initial_growth',0.06,null,'ratio','scenario',jsonb_build_object()),
    ('bear','terminal_growth',0.02,null,'ratio','scenario',jsonb_build_object()),
    ('bear','discount_rate',0.10,null,'ratio','scenario',jsonb_build_object()),
    ('base','initial_growth',0.10,null,'ratio','scenario',jsonb_build_object()),
    ('base','terminal_growth',0.025,null,'ratio','scenario',jsonb_build_object()),
    ('base','discount_rate',0.09,null,'ratio','scenario',jsonb_build_object()),
    ('bull','initial_growth',0.14,null,'ratio','scenario',jsonb_build_object()),
    ('bull','terminal_growth',0.03,null,'ratio','scenario',jsonb_build_object()),
    ('bull','discount_rate',0.085,null,'ratio','scenario',jsonb_build_object())
) as v(scenario, assumption_key, value_numeric, value_text, unit, source_kind, provenance)
where exists (
    select 1 from model.valuation_runs
    where run_id = '40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid
)
and not exists (
    select 1 from model.run_assumptions a
    where a.run_id = '40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid
      and a.scenario = v.scenario
      and a.assumption_key = v.assumption_key
);

with eligible_facts as (
    select
        max(f.value_numeric) filter (where f.metric_code = 'operating_cash_flow') as base_owner_earnings,
        max(f.value_numeric) filter (where f.metric_code = 'net_income_parent') as net_income_parent,
        max(f.value_numeric) filter (where f.metric_code = 'basic_eps') as basic_eps
    from pit.financial_facts f
    join master.issuers i on i.issuer_id = f.issuer_id
    where i.issuer_code = 'KWEICHOW_MOUTAI'
      and f.period_end = '2020-12-31'::date
      and f.available_at <= '2021-03-31T16:00:00Z'::timestamptz
),
scenarios as (
    select * from (values
        ('bear'::text, 0.06::numeric, 0.02::numeric, 0.10::numeric),
        ('base'::text, 0.10::numeric, 0.025::numeric, 0.09::numeric),
        ('bull'::text, 0.14::numeric, 0.03::numeric, 0.085::numeric)
    ) as s(scenario, initial_growth, terminal_growth, discount_rate)
),
growth_path as (
    select
        s.*,
        y.year_no,
        case
          when y.year_no <= 5 then s.initial_growth
          else s.initial_growth -
               (s.initial_growth - s.terminal_growth) * ((y.year_no - 5)::numeric / 5::numeric)
        end as growth_rate
    from scenarios s
    cross join generate_series(1, 10) as y(year_no)
),
forecast as (
    select
        g.*,
        f.base_owner_earnings,
        f.net_income_parent / nullif(f.basic_eps, 0) as shares_estimate,
        f.base_owner_earnings * exp(
            sum(ln(1 + g.growth_rate)) over (
                partition by g.scenario order by g.year_no
                rows between unbounded preceding and current row
            )
        ) as owner_earnings
    from growth_path g
    cross join eligible_facts f
),
aggregated as (
    select
        scenario,
        max(initial_growth) as initial_growth,
        max(terminal_growth) as terminal_growth,
        max(discount_rate) as discount_rate,
        max(base_owner_earnings) as base_owner_earnings,
        max(shares_estimate) as shares_estimate,
        sum(owner_earnings / power(1 + discount_rate, year_no)) as pv_explicit,
        max(owner_earnings) filter (where year_no = 10) as year_10_owner_earnings
    from forecast
    group by scenario
),
valued as (
    select
        *,
        year_10_owner_earnings * (1 + terminal_growth) /
            (discount_rate - terminal_growth) as terminal_value,
        year_10_owner_earnings * (1 + terminal_growth) /
            (discount_rate - terminal_growth) / power(1 + discount_rate, 10) as pv_terminal
    from aggregated
),
outputs as (
    select
        scenario,
        base_owner_earnings,
        shares_estimate,
        pv_explicit + pv_terminal as enterprise_value,
        pv_explicit + pv_terminal as equity_value,
        (pv_explicit + pv_terminal) / shares_estimate as value_per_share,
        pv_terminal / (pv_explicit + pv_terminal) as terminal_value_share
    from valued
)
insert into model.valuation_outputs
    (run_id, scenario, output_key, value_numeric, unit, metadata)
select
    '40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid,
    o.scenario,
    x.output_key,
    x.value_numeric,
    x.unit,
    jsonb_build_object(
        'methodology_quality', 'prototype_only',
        'owner_earnings_proxy', 'operating_cash_flow',
        'shares_proxy', 'net_income_parent/basic_eps',
        'net_cash_assumption', 0
    )
from outputs o
cross join lateral (values
    ('base_owner_earnings_proxy', o.base_owner_earnings, 'CNY'),
    ('shares_outstanding_estimate', o.shares_estimate, 'shares'),
    ('enterprise_value', o.enterprise_value, 'CNY'),
    ('equity_value', o.equity_value, 'CNY'),
    ('intrinsic_value_per_share', o.value_per_share, 'CNY/share'),
    ('terminal_value_share', o.terminal_value_share, 'ratio')
) as x(output_key, value_numeric, unit)
where not exists (
    select 1 from model.valuation_outputs existing
    where existing.run_id = '40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid
      and existing.scenario = o.scenario
      and existing.output_key = x.output_key
);

update model.valuation_runs vr
set status = 'completed_proxy',
    completed_at = now(),
    output_hash = (
        select md5(string_agg(
            o.scenario || '|' || o.output_key || '|' || coalesce(o.value_numeric::text, ''),
            '||' order by o.scenario, o.output_key
        ))
        from model.valuation_outputs o
        where o.run_id = vr.run_id
    ),
    error_text = 'Prototype-only output. The formal run remains blocked until the open data-quality issue is resolved.'
where vr.run_id = '40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid;

insert into audit.run_lineage
    (run_type, run_id, input_type, input_id, input_hash, metadata)
select
    'valuation_proxy',
    vr.run_id,
    'data_snapshot',
    vr.snapshot_id::text,
    vr.input_hash,
    jsonb_build_object('methodology_quality','prototype_only')
from model.valuation_runs vr
where vr.run_id = '40c77d91-6827-4ed0-b683-7a0fa355ca71'::uuid
  and not exists (
      select 1 from audit.run_lineage rl
      where rl.run_type = 'valuation_proxy'
        and rl.run_id = vr.run_id
        and rl.input_type = 'data_snapshot'
  );

commit;
