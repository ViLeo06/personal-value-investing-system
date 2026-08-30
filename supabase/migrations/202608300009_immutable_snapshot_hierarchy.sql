begin;

alter table audit.data_snapshots
  add column if not exists snapshot_kind text not null default 'generic',
  add column if not exists parent_snapshot_id uuid references audit.data_snapshots(snapshot_id),
  add column if not exists is_frozen boolean not null default false,
  add column if not exists frozen_at timestamptz,
  add column if not exists notes text;

create index if not exists data_snapshots_parent_idx
  on audit.data_snapshots(parent_snapshot_id);
create index if not exists data_snapshots_kind_asof_idx
  on audit.data_snapshots(snapshot_kind,as_of_at);

create or replace function audit.reject_frozen_snapshot_item_change()
returns trigger
language plpgsql
security invoker
set search_path=pg_catalog
as $$
declare
  v_snapshot_id uuid;
  v_is_frozen boolean;
begin
  v_snapshot_id:=coalesce(new.snapshot_id,old.snapshot_id);
  select ds.is_frozen into v_is_frozen
  from audit.data_snapshots ds where ds.snapshot_id=v_snapshot_id;
  if coalesce(v_is_frozen,false) then
    raise exception 'snapshot % is frozen; membership cannot change',v_snapshot_id;
  end if;
  return coalesce(new,old);
end;
$$;

create or replace function audit.reject_frozen_snapshot_change()
returns trigger
language plpgsql
security invoker
set search_path=pg_catalog
as $$
begin
  if tg_op='DELETE' and old.is_frozen then
    raise exception 'snapshot % is frozen; deletion is forbidden',old.snapshot_id;
  end if;
  if tg_op='UPDATE' and old.is_frozen then
    if new.snapshot_id is distinct from old.snapshot_id
       or new.as_of_at is distinct from old.as_of_at
       or new.cutoff_policy_version is distinct from old.cutoff_policy_version
       or new.manifest is distinct from old.manifest
       or new.snapshot_hash is distinct from old.snapshot_hash
       or new.snapshot_kind is distinct from old.snapshot_kind
       or new.parent_snapshot_id is distinct from old.parent_snapshot_id
       or new.is_frozen is distinct from old.is_frozen
       or new.frozen_at is distinct from old.frozen_at then
      raise exception 'snapshot % is frozen; protected fields cannot change',old.snapshot_id;
    end if;
  end if;
  return coalesce(new,old);
end;
$$;

revoke all on function audit.reject_frozen_snapshot_item_change() from public,anon,authenticated;
revoke all on function audit.reject_frozen_snapshot_change() from public,anon,authenticated;

drop trigger if exists snapshot_items_reject_frozen_change on audit.snapshot_items;
create trigger snapshot_items_reject_frozen_change
before insert or update or delete on audit.snapshot_items
for each row execute function audit.reject_frozen_snapshot_item_change();

drop trigger if exists data_snapshots_reject_frozen_change on audit.data_snapshots;
create trigger data_snapshots_reject_frozen_change
before update or delete on audit.data_snapshots
for each row execute function audit.reject_frozen_snapshot_change();

commit;
