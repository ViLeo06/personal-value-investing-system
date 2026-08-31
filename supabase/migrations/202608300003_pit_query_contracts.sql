begin;

create or replace function pit.financial_facts_as_of(
    p_issuer_id uuid,
    p_as_of_at timestamptz
)
returns setof pit.financial_facts
language sql
stable
security invoker
set search_path = ''
as $$
    select distinct on (
        f.issuer_id,
        f.statement_scope,
        f.statement_type,
        f.metric_code,
        f.period_start,
        f.period_end
    )
        f.*
    from pit.financial_facts f
    where f.issuer_id = p_issuer_id
      and f.available_at <= p_as_of_at
    order by
        f.issuer_id,
        f.statement_scope,
        f.statement_type,
        f.metric_code,
        f.period_start,
        f.period_end,
        f.available_at desc,
        f.revision_no desc,
        f.ingested_at desc,
        f.fact_id desc;
$$;

create or replace function pit.market_bars_as_of(
    p_security_id uuid,
    p_as_of_at timestamptz,
    p_start_date date default null,
    p_end_date date default null
)
returns setof pit.market_bars
language sql
stable
security invoker
set search_path = ''
as $$
    select distinct on (m.security_id, m.trade_date)
        m.*
    from pit.market_bars m
    join raw.data_sources s on s.source_id = m.source_id
    where m.security_id = p_security_id
      and m.available_at <= p_as_of_at
      and (p_start_date is null or m.trade_date >= p_start_date)
      and (p_end_date is null or m.trade_date <= p_end_date)
    order by
        m.security_id,
        m.trade_date,
        s.priority asc,
        m.available_at desc,
        m.ingested_at desc,
        m.bar_id desc;
$$;

create or replace function pit.corporate_actions_as_of(
    p_security_id uuid,
    p_as_of_at timestamptz
)
returns setof pit.corporate_actions
language sql
stable
security invoker
set search_path = ''
as $$
    select distinct on (
        c.security_id,
        c.action_type,
        coalesce(c.effective_date, c.ex_date, c.record_date, c.payment_date),
        coalesce(c.source_document_id::text, c.record_hash, c.action_id::text)
    )
        c.*
    from pit.corporate_actions c
    where c.security_id = p_security_id
      and c.available_at <= p_as_of_at
    order by
        c.security_id,
        c.action_type,
        coalesce(c.effective_date, c.ex_date, c.record_date, c.payment_date),
        coalesce(c.source_document_id::text, c.record_hash, c.action_id::text),
        c.available_at desc,
        c.action_id desc;
$$;

create or replace function audit.financial_snapshot_manifest(
    p_issuer_id uuid,
    p_as_of_at timestamptz,
    p_policy_version text default 'pit_cutoff_v1'
)
returns table(manifest jsonb, snapshot_hash text)
language sql
stable
security invoker
set search_path = ''
as $$
    with eligible as (
        select *
        from pit.financial_facts_as_of(p_issuer_id, p_as_of_at)
    ), packed as (
        select coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'fact_id', e.fact_id,
                    'statement_scope', e.statement_scope,
                    'statement_type', e.statement_type,
                    'metric_code', e.metric_code,
                    'period_start', e.period_start,
                    'period_end', e.period_end,
                    'value_numeric', e.value_numeric,
                    'value_text', e.value_text,
                    'unit', e.unit,
                    'currency', e.currency,
                    'available_at', e.available_at,
                    'revision_no', e.revision_no,
                    'source_document_id', e.source_document_id,
                    'record_hash', e.record_hash
                ) order by
                    e.statement_scope,
                    e.statement_type,
                    e.metric_code,
                    e.period_start,
                    e.period_end,
                    e.available_at,
                    e.revision_no
            ),
            '[]'::jsonb
        ) as facts
        from eligible e
    ), built as (
        select jsonb_build_object(
            'issuer_id', p_issuer_id,
            'as_of_at', p_as_of_at,
            'cutoff_policy_version', p_policy_version,
            'fact_count', jsonb_array_length(p.facts),
            'facts', p.facts
        ) as manifest
        from packed p
    )
    select
        b.manifest,
        encode(extensions.digest(convert_to(b.manifest::text, 'UTF8'), 'sha256'), 'hex')
    from built b;
$$;

revoke all on function pit.financial_facts_as_of(uuid, timestamptz)
    from public, anon, authenticated;
revoke all on function pit.market_bars_as_of(uuid, timestamptz, date, date)
    from public, anon, authenticated;
revoke all on function pit.corporate_actions_as_of(uuid, timestamptz)
    from public, anon, authenticated;
revoke all on function audit.financial_snapshot_manifest(uuid, timestamptz, text)
    from public, anon, authenticated;

grant execute on function pit.financial_facts_as_of(uuid, timestamptz) to service_role;
grant execute on function pit.market_bars_as_of(uuid, timestamptz, date, date) to service_role;
grant execute on function pit.corporate_actions_as_of(uuid, timestamptz) to service_role;
grant execute on function audit.financial_snapshot_manifest(uuid, timestamptz, text) to service_role;

commit;
