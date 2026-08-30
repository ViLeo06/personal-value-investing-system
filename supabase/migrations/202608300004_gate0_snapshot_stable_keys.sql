begin;

alter table audit.snapshot_items
    add column if not exists input_key text;

update audit.snapshot_items si
set input_key=coalesce(
    f.source_fact_key,
    concat_ws('|',f.issuer_id::text,f.statement_scope,f.statement_type,
              f.metric_code,coalesce(f.period_start::text,''),f.period_end::text,
              coalesce(f.fiscal_period,''),f.revision_no::text,f.available_at::text),
    concat_ws('|',si.input_type,si.input_id)
)
from pit.financial_facts f
where si.input_type='pit.financial_facts'
  and si.input_id=f.fact_id::text
  and si.input_key is null;

update audit.snapshot_items
set input_key=concat_ws('|',input_type,input_id)
where input_key is null;

alter table audit.snapshot_items
    alter column input_key set not null;

create unique index if not exists snapshot_items_stable_key_uq
    on audit.snapshot_items(snapshot_id,input_type,input_key);
create index if not exists snapshot_items_key_lookup_idx
    on audit.snapshot_items(input_type,input_key);

with digest as (
    select snapshot_id,
           count(*)::int as item_count,
           md5(string_agg(concat_ws('|',input_type,input_key,coalesce(input_hash,'')),
                          '||' order by input_type,input_key)) as membership_hash
    from audit.snapshot_items
    group by snapshot_id
)
update audit.data_snapshots ds
set manifest=ds.manifest || jsonb_build_object(
      'snapshot_item_count',d.item_count,
      'membership_hash',d.membership_hash,
      'membership_hash_version','stable_input_key_v1',
      'membership_materialized',true
    )
from digest d
where ds.snapshot_id=d.snapshot_id;

commit;
