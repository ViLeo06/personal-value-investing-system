do $$
begin
    -- Supabase projects already contain these roles. A plain PostgreSQL
    -- clean-room database does not, but later migrations intentionally revoke
    -- privileges from them. Creating missing NOLOGIN compatibility roles makes
    -- the exact same migration chain replayable outside Supabase.
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then
        create role service_role nologin bypassrls;
    end if;
end $$;
