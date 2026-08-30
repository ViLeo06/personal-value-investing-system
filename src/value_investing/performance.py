"""Deterministic performance statistics over an audited NAV series."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from math import isfinite, sqrt
from statistics import mean, stdev
from typing import Sequence


@dataclass(frozen=True)
class NavObservation:
    trade_date: date
    nav: float
    benchmark_nav: float | None = None


@dataclass(frozen=True)
class PerformanceSummary:
    start_date: date
    end_date: date
    observations: int
    total_return: float
    annualized_return: float
    annualized_volatility: float | None
    maximum_drawdown: float
    benchmark_total_return: float | None
    benchmark_annualized_return: float | None
    annualized_excess_return: float | None


def _annualized(start: float, end: float, days: int) -> float:
    if start <= 0 or end < 0:
        raise ValueError("NAV start must be positive and end non-negative")
    if days <= 0:
        raise ValueError("performance horizon must be positive")
    if end == 0:
        return -1.0
    return (end / start) ** (365.2425 / days) - 1.0


def performance_summary(
    observations: Sequence[NavObservation],
    *,
    trading_days_per_year: float = 252.0,
) -> PerformanceSummary:
    if len(observations) < 2:
        raise ValueError("at least two NAV observations are required")
    if trading_days_per_year <= 0 or not isfinite(trading_days_per_year):
        raise ValueError("trading days per year must be finite and positive")
    ordered = sorted(observations, key=lambda row: row.trade_date)
    if list(observations) != ordered:
        raise ValueError("NAV observations must be chronological")
    if len({row.trade_date for row in ordered}) != len(ordered):
        raise ValueError("NAV dates must be unique")
    if not all(isfinite(row.nav) and row.nav >= 0 for row in ordered):
        raise ValueError("NAV values must be finite and non-negative")
    benchmark_flags = [row.benchmark_nav is not None for row in ordered]
    if any(benchmark_flags) and not all(benchmark_flags):
        raise ValueError("benchmark NAV must be present for every row or none")
    if all(benchmark_flags) and not all(
        isfinite(row.benchmark_nav) and row.benchmark_nav >= 0  # type: ignore[arg-type]
        for row in ordered
    ):
        raise ValueError("benchmark NAV values must be finite and non-negative")

    start = ordered[0]
    end = ordered[-1]
    horizon_days = (end.trade_date - start.trade_date).days
    total_return = end.nav / start.nav - 1.0
    annualized_return = _annualized(start.nav, end.nav, horizon_days)

    daily_returns: list[float] = []
    peak = ordered[0].nav
    maximum_drawdown = 0.0
    for previous, current in zip(ordered, ordered[1:], strict=True):
        if previous.nav <= 0:
            raise ValueError("NAV cannot recover from zero in a simple return series")
        daily_returns.append(current.nav / previous.nav - 1.0)
        peak = max(peak, current.nav)
        drawdown = current.nav / peak - 1.0 if peak > 0 else -1.0
        maximum_drawdown = min(maximum_drawdown, drawdown)
    annualized_volatility = (
        stdev(daily_returns) * sqrt(trading_days_per_year)
        if len(daily_returns) >= 2
        else None
    )

    benchmark_total: float | None = None
    benchmark_annualized: float | None = None
    excess: float | None = None
    if all(benchmark_flags):
        benchmark_start = start.benchmark_nav
        benchmark_end = end.benchmark_nav
        assert benchmark_start is not None and benchmark_end is not None
        if benchmark_start <= 0:
            raise ValueError("benchmark start NAV must be positive")
        benchmark_total = benchmark_end / benchmark_start - 1.0
        benchmark_annualized = _annualized(
            benchmark_start, benchmark_end, horizon_days
        )
        excess = annualized_return - benchmark_annualized

    return PerformanceSummary(
        start_date=start.trade_date,
        end_date=end.trade_date,
        observations=len(ordered),
        total_return=total_return,
        annualized_return=annualized_return,
        annualized_volatility=annualized_volatility,
        maximum_drawdown=maximum_drawdown,
        benchmark_total_return=benchmark_total,
        benchmark_annualized_return=benchmark_annualized,
        annualized_excess_return=excess,
    )
