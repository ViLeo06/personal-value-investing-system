-- Required named parameters: $universe_code, $decision_date
-- Input views/tables: backtest_universes, backtest_universe_memberships

select
    u.universe_code,
    m.security_id,
    m.valid_from,
    m.valid_to,
    m.eligibility_reason
from backtest_universes u
join backtest_universe_memberships m using (universe_id)
where u.universe_code = $universe_code
  and m.valid_from <= $decision_date
  and (m.valid_to is null or m.valid_to >= $decision_date)
order by m.security_id;
