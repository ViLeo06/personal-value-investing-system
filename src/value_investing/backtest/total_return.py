"""Single-security cash-dividend holding ledger.

This module is intentionally small and deterministic. It does not fetch data,
choose securities or generate signals. Corporate-action dates and transaction
costs must be supplied by the caller with explicit provenance.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from math import isfinite
from statistics import stdev
from typing import Iterable, Mapping, Sequence


@dataclass(frozen=True, slots=True)
class PriceObservation:
    trade_date: date
    close_price: float
    dividend_per_share: float = 0.0

    def validate(self) -> None:
        if not isfinite(self.close_price) or self.close_price <= 0:
            raise ValueError("close_price must be positive and finite")
        if not isfinite(self.dividend_per_share) or self.dividend_per_share < 0:
            raise ValueError("dividend_per_share must be finite and non-negative")


@dataclass(frozen=True, slots=True)
class DailyHoldingPoint:
    trade_date: date
    close_price: float
    cumulative_dividend_per_share: float
    quantity: float
    market_value: float
    cash_value: float
    nav: float
    daily_return: float
    drawdown: float


@dataclass(frozen=True, slots=True)
class HoldingResult:
    initial_capital: float
    final_nav: float
    gross_price_return: float
    cash_dividend_return: float
    net_liquidation_total_return: float
    net_liquidation_cagr: float
    max_drawdown: float
    annualized_volatility: float | None
    cash_dividends_per_share: float
    entry_fees: float
    exit_fees: float
    daily: tuple[DailyHoldingPoint, ...]


def _require_positive(name: str, value: float) -> None:
    if not isfinite(value) or value <= 0:
        raise ValueError(f"{name} must be positive and finite")


def simulate_cash_dividend_hold(
    *,
    start_date: date,
    start_open_price: float,
    quantity: float,
    observations: Iterable[PriceObservation],
    entry_fees: float,
    exit_fees: float,
    liquidate_at_end: bool = True,
    annualization_days: float = 365.25,
    trading_days_per_year: float = 252.0,
) -> HoldingResult:
    """Simulate buy-at-open, hold, cash dividends, and terminal liquidation.

    Dividend cash is credited on the date supplied in each observation. For a
    formal run, callers should use the official payment date. Using ex-date is
    allowed only when the resulting run is explicitly tagged provisional.
    """

    _require_positive("start_open_price", start_open_price)
    _require_positive("quantity", quantity)
    if not all(isfinite(value) and value >= 0 for value in (entry_fees, exit_fees)):
        raise ValueError("fees must be finite and non-negative")
    if annualization_days <= 0 or trading_days_per_year <= 0:
        raise ValueError("annualization constants must be positive")

    ordered = sorted(observations, key=lambda item: item.trade_date)
    if not ordered:
        raise ValueError("observations must not be empty")
    if ordered[0].trade_date < start_date:
        raise ValueError("observations must start on or after start_date")
    if len({item.trade_date for item in ordered}) != len(ordered):
        raise ValueError("duplicate trade dates are not allowed")
    for item in ordered:
        item.validate()

    initial_capital = quantity * start_open_price + entry_fees
    cumulative_dividend = 0.0
    previous_nav = initial_capital
    running_peak = initial_capital
    points: list[DailyHoldingPoint] = []

    for index, observation in enumerate(ordered):
        cumulative_dividend += observation.dividend_per_share
        is_last = index == len(ordered) - 1
        if is_last and liquidate_at_end:
            remaining_quantity = 0.0
            market_value = 0.0
            cash_value = (
                quantity * observation.close_price
                + quantity * cumulative_dividend
                - exit_fees
            )
        else:
            remaining_quantity = quantity
            market_value = quantity * observation.close_price
            cash_value = quantity * cumulative_dividend
        nav = market_value + cash_value
        daily_return = nav / previous_nav - 1.0
        running_peak = max(running_peak, nav)
        drawdown = nav / running_peak - 1.0
        points.append(
            DailyHoldingPoint(
                trade_date=observation.trade_date,
                close_price=observation.close_price,
                cumulative_dividend_per_share=cumulative_dividend,
                quantity=remaining_quantity,
                market_value=market_value,
                cash_value=cash_value,
                nav=nav,
                daily_return=daily_return,
                drawdown=drawdown,
            )
        )
        previous_nav = nav

    first_close = ordered[0].close_price
    final_close = ordered[-1].close_price
    final_nav = points[-1].nav
    elapsed_days = (ordered[-1].trade_date - start_date).days
    if elapsed_days <= 0:
        raise ValueError("holding period must span at least one calendar day")
    daily_returns = [point.daily_return for point in points]
    annualized_volatility = (
        stdev(daily_returns) * trading_days_per_year**0.5
        if len(daily_returns) >= 2
        else None
    )

    return HoldingResult(
        initial_capital=initial_capital,
        final_nav=final_nav,
        gross_price_return=final_close / start_open_price - 1.0,
        cash_dividend_return=cumulative_dividend / start_open_price,
        net_liquidation_total_return=final_nav / initial_capital - 1.0,
        net_liquidation_cagr=(final_nav / initial_capital)
        ** (annualization_days / elapsed_days)
        - 1.0,
        max_drawdown=min(point.drawdown for point in points),
        annualized_volatility=annualized_volatility,
        cash_dividends_per_share=cumulative_dividend,
        entry_fees=entry_fees,
        exit_fees=exit_fees,
        daily=tuple(points),
    )


def align_daily_returns(
    left: Sequence[DailyHoldingPoint],
    right: Sequence[DailyHoldingPoint],
) -> tuple[tuple[date, float, float], ...]:
    """Inner-align two ledgers by trade date without forward-filling returns."""

    right_by_date: Mapping[date, DailyHoldingPoint] = {
        point.trade_date: point for point in right
    }
    return tuple(
        (point.trade_date, point.daily_return, right_by_date[point.trade_date].daily_return)
        for point in left
        if point.trade_date in right_by_date
    )
