begin;

create or replace function pit.ignore_duplicate_legacy_proxy_corporate_action()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
    -- Legacy workbook bridge rows use month-level proxy dates and fixed hashes.
    -- After an official-evidence backfill upgrades the canonical row, rerunning
    -- the bridge would otherwise recreate the obsolete proxy row under its old
    -- hash. Suppress only that narrow legacy duplicate; formal source revisions
    -- and non-legacy corporate actions remain insertable.
    if new.metadata ->> 'source_date_precision' = 'month_proxy'
       and exists (
           select 1
           from pit.corporate_actions existing
           where existing.security_id = new.security_id
             and existing.action_type = new.action_type
             and existing.cash_amount_per_share is not distinct from new.cash_amount_per_share
             and existing.currency is not distinct from new.currency
       ) then
        return null;
    end if;

    return new;
end;
$$;

revoke all on function pit.ignore_duplicate_legacy_proxy_corporate_action()
from public, anon, authenticated;

drop trigger if exists ignore_duplicate_legacy_proxy_corporate_action
on pit.corporate_actions;

create trigger ignore_duplicate_legacy_proxy_corporate_action
before insert on pit.corporate_actions
for each row
execute function pit.ignore_duplicate_legacy_proxy_corporate_action();

commit;
