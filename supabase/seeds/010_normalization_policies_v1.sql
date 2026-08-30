begin;

create extension if not exists pgcrypto;

with policies(policy_code, semantic_version, model_family, configuration, notes) as (
    values
    (
        'pit_revision_selection',
        '1.0.0',
        null,
        jsonb_build_object(
            'eligibility', 'available_at <= cutoff',
            'ordering', jsonb_build_array('available_at desc','revision_no desc','record_hash desc'),
            'mutation', 'append_only'
        ),
        'Select the latest version actually available at the historical cutoff; later corrections remain separate revisions.'
    ),
    (
        'cumulative_to_standalone',
        '1.0.0',
        null,
        jsonb_build_object(
            'formula', 'current cumulative - prior cumulative',
            'requires_same_period_start', true,
            'requires_same_unit_currency', true
        ),
        'Convert cumulative interim flows to standalone periods with explicit lineage.'
    ),
    (
        'owner_earnings_normalization',
        '1.0.0',
        'owner_earnings_dcf',
        jsonb_build_object(
            'formula', 'operating_cash_flow - maintenance_capex',
            'maintenance_capex', 'versioned analyst normalization with official-fact lineage',
            'share_denominator', 'security-level period-end shares'
        ),
        'Consumer-company owner earnings; maintenance capital spending cannot be hidden in a formula.'
    ),
    (
        'platform_fcff_normalization',
        '1.0.0',
        'fcff_sotp',
        jsonb_build_object(
            'nopat', 'normalized EBIT x (1 - normalized tax rate)',
            'reinvestment', 'incremental revenue / sales_to_capital',
            'non_operating_assets', 'valued separately from operating FCFF',
            'share_denominator', 'security-level period-end shares'
        ),
        'Platform operating FCFF and SOTP bridge are separated.'
    ),
    (
        'value_driver_normalization',
        '1.0.0',
        'value_driver_fcff',
        jsonb_build_object(
            'identity', 'growth = reinvestment_rate x RONIC',
            'nopat', 'normalized EBIT x (1 - normalized tax rate)',
            'invested_capital', 'operating capital under versioned policy',
            'ronic_window', 'documented incremental measurement window'
        ),
        'Capital-intensive manufacturing normalization with explicit capital efficiency.'
    ),
    (
        'bank_residual_income_normalization',
        '1.0.0',
        'residual_income',
        jsonb_build_object(
            'book_value_per_share', 'parent common equity / security shares',
            'roe', 'parent net income / average parent common equity',
            'payout_ratio', 'common dividends / parent net income',
            'primary_valuation', 'book value plus discounted residual income'
        ),
        'Bank normalization centered on book value, ROE, payout and regulatory/asset-quality drivers.'
    )
), prepared as (
    select
        policy_code,
        semantic_version,
        model_family,
        configuration,
        encode(digest(convert_to(configuration::text, 'UTF8'), 'sha256'), 'hex') as content_hash,
        notes
    from policies
)
insert into fundamentals.normalization_policies
    (policy_code, semantic_version, model_family, status, configuration, content_hash, notes, frozen_at)
select
    policy_code,
    semantic_version,
    model_family,
    'frozen',
    configuration,
    content_hash,
    notes,
    timestamptz '2026-08-30T00:00:00Z'
from prepared
on conflict (policy_code, semantic_version) do update set
    model_family = excluded.model_family,
    status = excluded.status,
    configuration = excluded.configuration,
    content_hash = excluded.content_hash,
    notes = excluded.notes,
    frozen_at = excluded.frozen_at;

commit;
