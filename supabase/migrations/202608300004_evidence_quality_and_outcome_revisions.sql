begin;

alter table raw.documents
    add column if not exists available_at timestamptz,
    add column if not exists publication_precision text not null default 'unknown',
    add column if not exists evidence_quality text not null default 'unknown';

alter table raw.documents
    drop constraint if exists documents_available_after_publication_check,
    add constraint documents_available_after_publication_check
        check (available_at is null or published_at is null or available_at >= published_at),
    drop constraint if exists documents_publication_precision_check,
    add constraint documents_publication_precision_check
        check (publication_precision in ('exact','minute','date','estimated','unknown')),
    drop constraint if exists documents_evidence_quality_check,
    add constraint documents_evidence_quality_check
        check (evidence_quality in (
            'official_binary',
            'official_reference',
            'reconciled_archive',
            'derived_archive',
            'proxy',
            'unknown'
        ));

create index if not exists documents_available_at_idx
    on raw.documents(available_at);
create index if not exists documents_evidence_quality_idx
    on raw.documents(evidence_quality);

create table if not exists backtest.outcome_revisions (
    revision_id uuid primary key default gen_random_uuid(),
    outcome_id uuid not null
        references backtest.decision_outcomes(outcome_id) on delete cascade,
    revision_code text not null,
    supersedes_revision_id uuid
        references backtest.outcome_revisions(revision_id),
    is_current boolean not null default true,
    reconciled_at timestamptz not null default now(),
    start_price numeric check (start_price is null or start_price > 0),
    end_price numeric check (end_price is null or end_price >= 0),
    final_share_multiplier numeric
        check (final_share_multiplier is null or final_share_multiplier > 0),
    terminal_value numeric check (terminal_value is null or terminal_value >= 0),
    total_return numeric,
    annualized_return numeric,
    benchmark_annualized_return numeric,
    excess_return numeric,
    source_quality text not null
        check (source_quality in ('official','reconciled','provisional','legacy_proxy')),
    reconciliation_payload jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    unique (outcome_id, revision_code)
);

create index if not exists outcome_revisions_outcome_idx
    on backtest.outcome_revisions(outcome_id, reconciled_at desc);
create unique index if not exists outcome_revisions_one_current_uq
    on backtest.outcome_revisions(outcome_id)
    where is_current;

revoke all privileges on backtest.outcome_revisions from anon, authenticated;

commit;
