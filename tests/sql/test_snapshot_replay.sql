-- These queries must return zero rows in a valid Gate-0 database.

-- No future information may enter a snapshot.
select si.*
from audit.snapshot_items si
join audit.data_snapshots ds using(snapshot_id)
where si.source_available_at > ds.as_of_at;

-- Stable business keys must be unique within a snapshot.
select snapshot_id,input_type,input_key,count(*)
from audit.snapshot_items
group by snapshot_id,input_type,input_key
having count(*)>1;

-- The stored digest must equal a fresh digest from stable input keys.
with calculated as (
  select snapshot_id,
         md5(string_agg(concat_ws('|',input_type,input_key,coalesce(input_hash,'')),
                        '||' order by input_type,input_key)) as membership_hash
  from audit.snapshot_items
  group by snapshot_id
)
select ds.snapshot_id,ds.manifest->>'membership_hash' as stored,c.membership_hash as calculated
from audit.data_snapshots ds
join calculated c using(snapshot_id)
where ds.manifest->>'membership_hash' is distinct from c.membership_hash;

-- The Moutai prototype freezes one evidence document and six financial facts.
select ds.snapshot_id,count(*) as item_count
from audit.data_snapshots ds
join audit.snapshot_items si using(snapshot_id)
where ds.snapshot_hash='9950df576f62d3a87aac8b7ee276a173'
group by ds.snapshot_id
having count(*)<>7;
