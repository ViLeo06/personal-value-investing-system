do $$
begin
    -- The clean-room PostgreSQL CI image does not include Supabase Storage.
    -- On Supabase, create/update a private bucket for immutable evidence bytes.
    if exists (
        select 1 from information_schema.schemata where schema_name = 'storage'
    ) then
        insert into storage.buckets
            (id, name, public, file_size_limit, allowed_mime_types)
        values (
            'research-evidence',
            'research-evidence',
            false,
            52428800,
            array[
                'application/pdf',
                'text/html',
                'application/json',
                'text/plain',
                'text/csv',
                'application/octet-stream'
            ]::text[]
        )
        on conflict (id) do update set
            name = excluded.name,
            public = false,
            file_size_limit = excluded.file_size_limit,
            allowed_mime_types = excluded.allowed_mime_types;
    end if;
end $$;
