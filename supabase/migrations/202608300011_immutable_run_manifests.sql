begin;

create table if not exists audit.run_manifests (
    manifest_id uuid primary key default gen_random_uuid(),
    run_type text not null
        check (run_type in ('valuation','backtest','normalization','ingestion')),
    run_id uuid not null,
    manifest jsonb not null,
    manifest_hash text not null,
    frozen_at timestamptz not null default now(),
    supersedes_manifest_id uuid references audit.run_manifests(manifest_id),
    notes text,
    unique (run_type,run_id,manifest_hash),
    check (jsonb_typeof(manifest)='object'),
    check (length(manifest_hash)=64)
);

create index if not exists run_manifests_run_idx
    on audit.run_manifests(run_type,run_id,frozen_at desc);
create index if not exists run_manifests_hash_idx
    on audit.run_manifests(manifest_hash);

create or replace function audit.reject_run_manifest_mutation()
returns trigger
language plpgsql
security invoker
set search_path=''
as $$
begin
    raise exception 'audit.run_manifests is append-only; insert a superseding manifest instead';
end;
$$;

revoke all on function audit.reject_run_manifest_mutation()
    from public,anon,authenticated;

drop trigger if exists reject_run_manifest_update on audit.run_manifests;
create trigger reject_run_manifest_update
before update or delete on audit.run_manifests
for each row execute function audit.reject_run_manifest_mutation();

revoke all on audit.run_manifests from public,anon,authenticated;

commit;
