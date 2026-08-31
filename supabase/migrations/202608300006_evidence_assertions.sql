begin;

create table if not exists audit.evidence_assertions (
    evidence_id uuid primary key default gen_random_uuid(),
    assertion_code text not null,
    subject_type text not null,
    subject_id text not null,
    as_of_at timestamptz,
    evidence_grade smallint not null
        check (evidence_grade between 0 and 3),
    status text not null default 'active'
        check (status in ('active','superseded','rejected','conflicted')),
    source_codes text[] not null default '{}',
    content_hashes text[] not null default '{}',
    unresolved_conflict boolean not null default false,
    details jsonb not null default '{}'::jsonb,
    asserted_at timestamptz not null default now(),
    asserted_by text not null default 'system',
    unique (assertion_code, subject_type, subject_id, as_of_at, asserted_at)
);

create index if not exists evidence_assertions_subject_idx
    on audit.evidence_assertions(subject_type, subject_id, as_of_at);
create index if not exists evidence_assertions_code_grade_idx
    on audit.evidence_assertions(assertion_code, evidence_grade, status);

revoke all on audit.evidence_assertions from public, anon, authenticated;

commit;
