begin;

create extension if not exists pgcrypto;

with payload as (
    select jsonb_build_array(
        jsonb_build_object('rule_code','PIT001','severity','critical','description','Decision cutoff is timezone-aware.'),
        jsonb_build_object('rule_code','PIT002','severity','critical','description','No financial fact in frozen lineage has available_at after the run cutoff.'),
        jsonb_build_object('rule_code','PIT003','severity','critical','description','No normalized fact in frozen lineage has available_at after the run cutoff.'),
        jsonb_build_object('rule_code','EVD001','severity','critical','description','Every required official evidence object has a content hash.'),
        jsonb_build_object('rule_code','EVD002','severity','warning','description','Required evidence bytes are retained in durable private object storage.'),
        jsonb_build_object('rule_code','MOD001','severity','error','description','All model-family required canonical metrics are present.'),
        jsonb_build_object('rule_code','MOD002','severity','error','description','Canonical metric units are compatible with the model contract.'),
        jsonb_build_object('rule_code','MOD003','severity','critical','description','Valuation input and output hashes are present and reproducible.'),
        jsonb_build_object('rule_code','PAR001','severity','critical','description','Formal runs reference a frozen parameter set.'),
        jsonb_build_object('rule_code','CAL001','severity','error','description','Execution and next-session logic reference a frozen calendar version.'),
        jsonb_build_object('rule_code','MKT001','severity','warning','description','Decision price is sourced from authoritative unadjusted market data.'),
        jsonb_build_object('rule_code','ACT001','severity','warning','description','Corporate actions are complete for the outcome window.'),
        jsonb_build_object('rule_code','RET001','severity','warning','description','Outcome uses exact daily total return rather than endpoint or annual proxies.'),
        jsonb_build_object('rule_code','PHS001','severity','critical','description','Phase A inputs and decisions were frozen before Phase B outcomes were revealed.'),
        jsonb_build_object('rule_code','REL001','severity','critical','description','Formal release manifest captures code, schema, data, model, parameters and dependencies.')
    ) as rules
), prepared as (
    select
        'gate0_quality_v1.0.0'::text as rule_set_version,
        rules,
        encode(digest(convert_to(rules::text, 'UTF8'), 'sha256'), 'hex') as content_hash
    from payload
)
insert into audit.quality_rule_sets
    (rule_set_version, status, rules, content_hash, notes, frozen_at)
select
    rule_set_version,
    'frozen',
    rules,
    content_hash,
    'Initial Gate-0 evidence, PIT, model, market, return and release readiness rules.',
    timestamptz '2026-08-30T00:00:00Z'
from prepared
on conflict (rule_set_version) do update set
    status = excluded.status,
    rules = excluded.rules,
    content_hash = excluded.content_hash,
    notes = excluded.notes,
    frozen_at = excluded.frozen_at;

commit;
