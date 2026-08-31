from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from math import sqrt
from statistics import pstdev
from typing import Mapping, Sequence


@dataclass(frozen=True, slots=True)
class PerformanceSummary:
    start_date: date
    end_date: date
    observations: int
    start_nav: float
    end_nav: float
    total_return: float
    cagr: float
    annualized_volatility: float | None
    max_drawdown: float
    benchmark_total_return: float | None
    excess_total_return: float | None
    tracking_error: float | None
    information_ratio: float | None


def _year_fraction(start_date: date, end_date: date) -> float:
    days = (end_date - start_date).days
    if days <= 0:
        raise ValueError("end_date must be after start_date")
    return days / 365.2425


def _returns(values: Sequence[float]) -> list[float]:
    result: list[float] = []
    for previous, current in zip(values, values[1:]):
        if previous <= 0:
            raise ValueError("NAV values must be positive")
        result.append(current / previous - 1.0)
    return result


def _max_drawdown(values: Sequence[float]) -> float:
    if not values:
        raise ValueError("values cannot be empty")
    peak = values[0]
    worst = 0.0
    for value in values:
        if value <= 0:
            raise ValueError("NAV values must be positive")
        peak = max(peak, value)
        worst = min(worst, value / peak - 1.0)
    return worst


def summarize_performance(
    nav_by_date: Mapping[date, float],
    *,
    benchmark_nav_by_date: Mapping[date, float] | None = None,
    periods_per_year: int = 252,
) -> PerformanceSummary:
    if periods_per_year <= 0:
        raise ValueError("periods_per_year must be positive")
    if len(nav_by_date) < 2:
        raise ValueError("At least two NAV observations are required")
    ordered = sorted(nav_by_date.items())
    dates = [item[0] for item in ordered]
    navs = [float(item[1]) for item in ordered]
    if any(value <= 0 for value in navs):
        raise ValueError("NAV values must be positive")

    total_return = navs[-1] / navs[0] - 1.0
    cagr = (navs[-1] / navs[0]) ** (1.0 / _year_fraction(dates[0], dates[-1])) - 1.0
    daily_returns = _returns(navs)
    volatility = (
        None
        if len(daily_returns) < 2
        else pstdev(daily_returns) * sqrt(periods_per_year)
    )

    benchmark_total_return: float | None = None
    excess_total_return: float | None = None
    tracking_error: float | None = None
    information_ratio: float | None = None

    if benchmark_nav_by_date is not None:
        common_dates = sorted(set(nav_by_date) & set(benchmark_nav_by_date))
        if len(common_dates) < 2:
            raise ValueError("Benchmark requires at least two common dates")
        portfolio_common = [float(nav_by_date[current]) for current in common_dates]
        benchmark_common = [float(benchmark_nav_by_date[current]) for current in common_dates]
        if any(value <= 0 for value in benchmark_common):
            raise ValueError("Benchmark NAV values must be positive")
        portfolio_returns = _returns(portfolio_common)
        benchmark_returns = _returns(benchmark_common)
        active_returns = [
            portfolio_return - benchmark_return
            for portfolio_return, benchmark_return in zip(
                portfolio_returns, benchmark_returns
            )
        ]
        benchmark_total_return = benchmark_common[-1] / benchmark_common[0] - 1.0
        excess_total_return = total_return - benchmark_total_return
        if len(active_returns) >= 2:
            tracking_error = pstdev(active_returns) * sqrt(periods_per_year)
            if tracking_error > 0:
                information_ratio = (
                    sum(active_returns) / len(active_returns) * periods_per_year
                ) / tracking_error

    return PerformanceSummary(
        start_date=dates[0],
        end_date=dates[-1],
        observations=len(navs),
        start_nav=navs[0],
        end_nav=navs[-1],
        total_return=total_return,
        cagr=cagr,
        annualized_volatility=volatility,
        max_drawdown=_max_drawdown(navs),
        benchmark_total_return=benchmark_total_return,
        excess_total_return=excess_total_return,
        tracking_error=tracking_error,
        information_ratio=information_ratio,
    )


def reconcile_attribution(
    *,
    total_return: float,
    effects: Mapping[str, float],
    tolerance: float = 1e-10,
) -> float:
    residual = total_return - sum(float(value) for value in effects.values())
    if abs(residual) > tolerance:
        raise ValueError(
            f"Attribution does not reconcile: residual={residual:.12g}, tolerance={tolerance}"
        )
    return residual
