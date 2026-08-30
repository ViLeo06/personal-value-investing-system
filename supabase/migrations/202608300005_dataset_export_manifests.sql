begin;

create table audit.dataset_exports (
    export_id uuid primary key default gen_random_uuid(),
    snapshot_id uuid not null
        references audit.data_snapshots(snapshot_id),
    dataset_name text not null,
    schema_version text not null,
    manifest_hash text not null unique,
    manifest jsonb not null,
    row_count bigint not null check (row_count >= 0),
    minimum_available_at timestamptz,
    maximum_available_at timestamptz,
    status text not null default 'created'
        check (status in ('created','validated','superseded','failed')),
    exported_at timestamptz not null default now(),
    validated_at timestamptz,
    error_text text,
    constraint dataset_exports_availability_check
        check (
            minimum_available_at is null
            or maximum_available_at is null
            or minimum_available_at <= maximum_available_at
        ),
    unique (snapshot_id, dataset_name, schema_version, manifest_hash)
);

create table audit.dataset_export_files (
    export_id uuid not null
        references audit.dataset_exports(export_id) on delete cascade,
    relative_path text not null,
    row_count bigint not null check (row_count >= 0),
    content_hash text not null,
    ordered_key_hash text,
    minimum_available_at timestamptz,
    maximum_available_at timestamptz,
    metadata jsonb not null default '{}'::jsonb,
    primary key (export_id, relative_path),
    constraint dataset_export_files_relative_path_check
        check (
            relative_path <> ''
            and left(relative_path, 1) <> '/'
            and position('..' in relative_path) = 0
        ),
    constraint dataset_export_files_availability_check
        check (
            minimum_available_at is null
            or maximum_available_at is null
            or minimum_available_at <= maximum_available_at
        )
);

create index dataset_exports_snapshot_dataset_idx
    on audit.dataset_exports(snapshot_id, dataset_name, schema_version);
create index dataset_export_files_content_hash_idx
    on audit.dataset_export_files(content_hash);

revoke all privileges on audit.dataset_exports,
    audit.dataset_export_files from anon, authenticated;

commit;
