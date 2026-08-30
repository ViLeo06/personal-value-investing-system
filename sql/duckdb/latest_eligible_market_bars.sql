-- Required named parameter: $decision_at
-- Input view/table: pit_market_bars

with eligible as (
    select *
    from pit_market_bars
    where available_at <= $decision_at
), ranked as (
    select
        *,
        row_number() over (
            partition by security_id, trade_date, source_id
            order by available_at desc, ingested_at desc
        ) as eligible_source_revision_rank
    from eligible
)
select * exclude (eligible_source_revision_rank)
from ranked
where eligible_source_revision_rank = 1;
