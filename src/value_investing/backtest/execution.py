from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
from typing import Iterable

from value_investing.data.market import MarketBar


@dataclass(frozen=True, slots=True)
class DecisionPriceContext:
    decision_at: datetime
    reference_trade_date: str
    reference_close: Decimal
    execution_trade_date: str
    execution_open: Decimal


def decision_and_execution_prices(
    bars: Iterable[MarketBar], decision_at: datetime
) -> DecisionPriceContext:
    """Separate observable reference price from subsequent execution price.

    The reference close is the latest bar available at the decision timestamp.
    The execution open is the first later trading session's open. The latter is an
    execution outcome and must never enter the frozen decision information set.
    """
    if decision_at.tzinfo is None or decision_at.utcoffset() is None:
        raise ValueError("decision_at must be timezone-aware")
    ordered = sorted(bars, key=lambda item: item.trade_date)
    eligible = [bar for bar in ordered if bar.available_at <= decision_at]
    if not eligible:
        raise ValueError("No observable reference bar at decision time")
    reference = eligible[-1]
    later = [bar for bar in ordered if bar.trade_date > reference.trade_date]
    if not later:
        raise ValueError("No later session is available for execution")
    execution = later[0]
    return DecisionPriceContext(
        decision_at=decision_at,
        reference_trade_date=reference.trade_date.isoformat(),
        reference_close=reference.close_price,
        execution_trade_date=execution.trade_date.isoformat(),
        execution_open=execution.open_price,
    )
