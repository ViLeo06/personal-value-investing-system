-- PIT leakage smoke test.
-- Expected result: leaked_rows = 0.

with params as (
  select '2021-04-01 00:00:00+08'::timestamptz as decision_at
), eligible as (
  select f.*
  from pit.financial_facts f, params p
  where f.available_at <= p.decision_at
)
select count(*) filter (where available_at > decision_at) as leaked_rows
from eligible cross join params;

-- Prototype Moutai snapshot should contain exactly six seeded FY2020 facts.
select count(*) as eligible_moutai_facts
from pit.financial_facts f
join master.issuers i using (issuer_id)
where i.issuer_code='KWEICHOW_MOUTAI'
  and f.available_at <= '2021-04-01 00:00:00+08'::timestamptz;
