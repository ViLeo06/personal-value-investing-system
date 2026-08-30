-- Required named parameter: $decision_at
-- Input view/table: pit_financial_facts
-- Filter on availability before ranking revisions. Reversing these steps leaks
-- present-day restatements into historical decisions.

with eligible as (
    select *
    from pit_financial_facts
    where available_at <= $decision_at
), ranked as (
    select
        *,
        row_number() over (
            partition by
                issuer_id,
                statement_scope,
                statement_type,
                metric_code,
                period_start,
                period_end,
                fiscal_period,
                fact_kind,
                unit,
                currency
            order by available_at desc, revision_no desc, ingested_at desc
        ) as eligible_revision_rank
    from eligible
)
select * exclude (eligible_revision_rank)
from ranked
where eligible_revision_rank = 1;
