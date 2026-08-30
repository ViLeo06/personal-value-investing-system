begin;

create table audit.evidence_objects (
    evidence_object_id uuid primary key default gen_random_uuid(),
    document_id uuid not null unique
        references raw.documents(document_id) on delete cascade,
    bucket_id text not null,
    object_path text not null,
    content_hash text not null,
    byte_size bigint not null check (byte_size >= 0),
    mime_type text not null,
    upload_status text not null default 'registered'
        check (upload_status in ('registered','uploaded','verified','failed','quarantined')),
    uploaded_at timestamptz,
    verified_at timestamptz,
    verification_method text,
    error_text text,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    constraint evidence_objects_path_check
        check (
            object_path <> ''
            and left(object_path,1) <> '/'
            and position('..' in object_path) = 0
        ),
    constraint evidence_objects_hash_check
        check (content_hash ~ '^[0-9a-f]{64}$'),
    constraint evidence_objects_status_time_check
        check (
            (upload_status='registered' and uploaded_at is null)
            or upload_status<>'registered'
        ),
    unique (bucket_id, object_path),
    unique (bucket_id, content_hash)
);

create index evidence_objects_status_idx
    on audit.evidence_objects(upload_status, created_at);
create index evidence_objects_hash_idx
    on audit.evidence_objects(content_hash);

revoke all privileges on audit.evidence_objects from anon, authenticated;

-- The vanilla PostgreSQL CI image has no Supabase Storage schema. On a real
-- Supabase project, create a private server-only bucket. No storage.objects
-- client policy is added, so publishable/anon/authenticated clients have no
-- access; service-side credentials perform ingestion.
do $$
begin
    if to_regclass('storage.buckets') is not null then
        execute $sql$
            insert into storage.buckets (
                id,name,public,file_size_limit,allowed_mime_types
            ) values (
                'research-evidence',
                'research-evidence',
                false,
                52428800,
                array[
                    'application/pdf',
                    'text/html',
                    'application/json',
                    'text/plain',
                    'application/zip'
                ]::text[]
            )
            on conflict (id) do update set
                public=false,
                file_size_limit=excluded.file_size_limit,
                allowed_mime_types=excluded.allowed_mime_types
        $sql$;
    end if;
end $$;

commit;
