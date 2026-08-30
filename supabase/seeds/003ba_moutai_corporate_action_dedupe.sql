begin;

-- The legacy bridge originally keyed Moutai corporate actions by proxy hashes.
-- Once seed 011 upgrades those records to official-date v2 hashes, a second
-- seed pass can make the legacy seed insert proxy duplicates again. Remove only
-- proxy rows whose economic business key is already represented by a v2 row.
delete from pit.corporate_actions proxy
using pit.corporate_actions canonical,
      master.securities security
where proxy.security_id = security.security_id
  and security.security_code = '600519.SH'
  and canonical.security_id = proxy.security_id
  and canonical.action_id <> proxy.action_id
  and canonical.action_type = proxy.action_type
  and canonical.cash_amount_per_share is not distinct from proxy.cash_amount_per_share
  and canonical.currency is not distinct from proxy.currency
  and canonical.metadata ->> 'record_hash_version' = 'corporate_action_v2'
  and coalesce(proxy.metadata ->> 'record_hash_version', '') <> 'corporate_action_v2';

commit;
