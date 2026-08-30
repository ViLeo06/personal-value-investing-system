begin;

create table if not exists audit.snapshot_items (
    snapshot_id uuid not null references audit.data_snapshots(snapshot_id) on delete cascade,
    input_type text not null,
    input_id text not null,
    input_hash text,
    source_available_at timestamptz,
    metadata jsonb not null default '{}'::jsonb,
    recorded_at timestamptz not null default now(),
    primary key (snapshot_id, input_type, input_id)
);

create index if not exists snapshot_items_type_idx
    on audit.snapshot_items (input_type, input_id);
create index if not exists snapshot_items_available_idx
    on audit.snapshot_items (snapshot_id, source_available_at);

revoke all on table audit.snapshot_items from anon, authenticated;

do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname='financial_facts_available_after_publish_chk'
          and conrelid='pit.financial_facts'::regclass
    ) then
        alter table pit.financial_facts
            add constraint financial_facts_available_after_publish_chk
            check (published_at is null or available_at >= published_at) not valid;
    end if;

    if not exists (
        select 1 from pg_constraint
        where conname='financial_facts_one_value_chk'
          and conrelid='pit.financial_facts'::regclass
    ) then
        alter table pit.financial_facts
            add constraint financial_facts_one_value_chk
            check (num_nonnulls(value_numeric,value_text)=1) not valid;
    end if;

    if not exists (
        select 1 from pg_constraint
        where conname='normalized_facts_one_value_chk'
          and conrelid='fundamentals.normalized_facts'::regclass
    ) then
        alter table fundamentals.normalized_facts
            add constraint normalized_facts_one_value_chk
            check (num_nonnulls(value_numeric,value_text)=1) not valid;
    end if;
end $$;

commit;
