begin;

create or replace function pit.segment_fact_versions_as_of(
    p_decision_at timestamptz
)
returns setof pit.segment_facts
language sql
stable
security invoker
set search_path = pg_catalog, pit
as $$
    select distinct on (
        sf.issuer_id,
        sf.segment_id,
        sf.metric_code,
        sf.period_start,
        sf.period_end,
        sf.fact_kind,
        sf.unit,
        sf.currency,
        sf.source_document_id,
        sf.source_fact_key
    ) sf.*
    from pit.segment_facts sf
    where sf.available_at <= p_decision_at
    order by
        sf.issuer_id,
        sf.segment_id,
        sf.metric_code,
        sf.period_start,
        sf.period_end,
        sf.fact_kind,
        sf.unit,
        sf.currency,
        sf.source_document_id,
        sf.source_fact_key,
        sf.available_at desc,
        sf.revision_no desc,
        sf.ingested_at desc,
        sf.segment_fact_id desc
$$;

create or replace function pit.share_class_fact_versions_as_of(
    p_decision_at timestamptz
)
returns setof pit.share_class_facts
language sql
stable
security invoker
set search_path = pg_catalog, pit
as $$
    select distinct on (
        scf.issuer_id,
        scf.security_id,
        scf.share_class_code,
        scf.period_end,
        scf.source_document_id,
        scf.source_fact_key
    ) scf.*
    from pit.share_class_facts scf
    where scf.available_at <= p_decision_at
    order by
        scf.issuer_id,
        scf.security_id,
        scf.share_class_code,
        scf.period_end,
        scf.source_document_id,
        scf.source_fact_key,
        scf.available_at desc,
        scf.revision_no desc,
        scf.ingested_at desc,
        scf.share_fact_id desc
$$;

create or replace function fundamentals.normalized_segment_fact_versions_as_of(
    p_decision_at timestamptz
)
returns setof fundamentals.normalized_segment_facts
language sql
stable
security invoker
set search_path = pg_catalog, fundamentals
as $$
    select distinct on (
        nsf.issuer_id,
        nsf.segment_id,
        nsf.metric_code,
        nsf.period_start,
        nsf.period_end,
        nsf.unit,
        nsf.currency,
        nsf.normalization_version
    ) nsf.*
    from fundamentals.normalized_segment_facts nsf
    where nsf.available_at <= p_decision_at
    order by
        nsf.issuer_id,
        nsf.segment_id,
        nsf.metric_code,
        nsf.period_start,
        nsf.period_end,
        nsf.unit,
        nsf.currency,
        nsf.normalization_version,
        nsf.available_at desc,
        nsf.created_at desc,
        nsf.normalized_segment_fact_id desc
$$;

revoke all on function pit.segment_fact_versions_as_of(timestamptz)
    from public, anon, authenticated;
revoke all on function pit.share_class_fact_versions_as_of(timestamptz)
    from public, anon, authenticated;
revoke all on function fundamentals.normalized_segment_fact_versions_as_of(timestamptz)
    from public, anon, authenticated;

grant execute on function pit.segment_fact_versions_as_of(timestamptz)
    to service_role;
grant execute on function pit.share_class_fact_versions_as_of(timestamptz)
    to service_role;
grant execute on function fundamentals.normalized_segment_fact_versions_as_of(timestamptz)
    to service_role;

commit;
