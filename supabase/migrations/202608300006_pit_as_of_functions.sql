begin;

create or replace function pit.financial_fact_versions_as_of(
    p_decision_at timestamptz
)
returns setof pit.financial_facts
language sql
stable
security invoker
set search_path = pg_catalog, pit
as $$
    select distinct on (
        ff.issuer_id,
        ff.statement_scope,
        ff.statement_type,
        ff.metric_code,
        ff.period_start,
        ff.period_end,
        ff.fiscal_period,
        ff.fact_kind,
        ff.unit,
        ff.currency,
        ff.source_document_id,
        ff.source_fact_key
    ) ff.*
    from pit.financial_facts ff
    where ff.available_at <= p_decision_at
    order by
        ff.issuer_id,
        ff.statement_scope,
        ff.statement_type,
        ff.metric_code,
        ff.period_start,
        ff.period_end,
        ff.fiscal_period,
        ff.fact_kind,
        ff.unit,
        ff.currency,
        ff.source_document_id,
        ff.source_fact_key,
        ff.available_at desc,
        ff.revision_no desc,
        ff.ingested_at desc,
        ff.fact_id desc
$$;

create or replace function pit.market_bar_versions_as_of(
    p_decision_at timestamptz
)
returns setof pit.market_bars
language sql
stable
security invoker
set search_path = pg_catalog, pit
as $$
    select distinct on (mb.security_id, mb.trade_date, mb.source_id) mb.*
    from pit.market_bars mb
    where mb.available_at <= p_decision_at
    order by
        mb.security_id,
        mb.trade_date,
        mb.source_id,
        mb.available_at desc,
        mb.ingested_at desc,
        mb.bar_id desc
$$;

create or replace function fundamentals.normalized_fact_versions_as_of(
    p_decision_at timestamptz
)
returns setof fundamentals.normalized_facts
language sql
stable
security invoker
set search_path = pg_catalog, fundamentals
as $$
    select distinct on (
        nf.issuer_id,
        nf.metric_code,
        nf.period_start,
        nf.period_end,
        nf.unit,
        nf.currency,
        nf.normalization_version
    ) nf.*
    from fundamentals.normalized_facts nf
    where nf.available_at <= p_decision_at
    order by
        nf.issuer_id,
        nf.metric_code,
        nf.period_start,
        nf.period_end,
        nf.unit,
        nf.currency,
        nf.normalization_version,
        nf.available_at desc,
        nf.created_at desc,
        nf.normalized_fact_id desc
$$;

revoke all on function pit.financial_fact_versions_as_of(timestamptz)
    from public, anon, authenticated;
revoke all on function pit.market_bar_versions_as_of(timestamptz)
    from public, anon, authenticated;
revoke all on function fundamentals.normalized_fact_versions_as_of(timestamptz)
    from public, anon, authenticated;

grant execute on function pit.financial_fact_versions_as_of(timestamptz)
    to service_role;
grant execute on function pit.market_bar_versions_as_of(timestamptz)
    to service_role;
grant execute on function fundamentals.normalized_fact_versions_as_of(timestamptz)
    to service_role;

commit;
