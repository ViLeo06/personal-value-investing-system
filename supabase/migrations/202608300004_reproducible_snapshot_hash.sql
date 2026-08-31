begin;

create or replace function audit.financial_snapshot_manifest(
    p_issuer_id uuid,
    p_as_of_at timestamptz,
    p_policy_version text default 'pit_cutoff_v3_content_hash'
)
returns table(manifest jsonb, snapshot_hash text)
language sql
stable
security invoker
set search_path = ''
as $$
    with eligible as (
        select
            f.statement_scope,
            f.statement_type,
            f.metric_code,
            f.metric_label,
            f.period_start,
            f.period_end,
            f.fiscal_year,
            f.fiscal_period,
            f.fact_kind,
            f.value_numeric,
            f.value_text,
            f.unit,
            f.currency,
            f.scale,
            f.published_at,
            f.available_at,
            f.revision_no,
            f.is_preliminary,
            f.source_fact_key,
            f.record_hash,
            d.content_hash as source_document_content_hash
        from pit.financial_facts_as_of(p_issuer_id, p_as_of_at) f
        left join raw.documents d on d.document_id = f.source_document_id
    ), packed as (
        select coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'statement_scope', e.statement_scope,
                    'statement_type', e.statement_type,
                    'metric_code', e.metric_code,
                    'metric_label', e.metric_label,
                    'period_start', e.period_start,
                    'period_end', e.period_end,
                    'fiscal_year', e.fiscal_year,
                    'fiscal_period', e.fiscal_period,
                    'fact_kind', e.fact_kind,
                    'value_numeric', e.value_numeric,
                    'value_text', e.value_text,
                    'unit', e.unit,
                    'currency', e.currency,
                    'scale', e.scale,
                    'published_at', e.published_at,
                    'available_at', e.available_at,
                    'revision_no', e.revision_no,
                    'is_preliminary', e.is_preliminary,
                    'source_fact_key', e.source_fact_key,
                    'record_hash', e.record_hash,
                    'source_document_content_hash', e.source_document_content_hash
                ) order by
                    e.statement_scope,
                    e.statement_type,
                    e.metric_code,
                    e.period_start,
                    e.period_end,
                    e.available_at,
                    e.revision_no,
                    coalesce(e.source_fact_key, ''),
                    coalesce(e.record_hash, '')
            ),
            '[]'::jsonb
        ) as facts
        from eligible e
    ), issuer_identity as (
        select issuer_code, legal_name
        from master.issuers
        where issuer_id = p_issuer_id
    ), built as (
        select jsonb_build_object(
            'issuer_code', i.issuer_code,
            'legal_name', i.legal_name,
            'as_of_at', p_as_of_at,
            'cutoff_policy_version', p_policy_version,
            'fact_count', jsonb_array_length(p.facts),
            'facts', p.facts
        ) as manifest
        from packed p
        cross join issuer_identity i
    )
    select
        b.manifest,
        encode(extensions.digest(convert_to(b.manifest::text, 'UTF8'), 'sha256'), 'hex')
    from built b;
$$;

revoke all on function audit.financial_snapshot_manifest(uuid, timestamptz, text)
    from public, anon, authenticated;
grant execute on function audit.financial_snapshot_manifest(uuid, timestamptz, text)
    to service_role;

commit;
