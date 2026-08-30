"""Transparent deterministic valuation primitives.

Domain-specific model families build on these functions; they intentionally do
not fetch data or decide assumptions.
"""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite
from typing import Callable, Sequence


@dataclass(frozen=True)
class DcfResult:
    enterprise_value: float
    pv_explicit_cash_flows: float
    pv_terminal_value: float
    terminal_value: float


def present_value(value: float, rate: float, periods: float) -> float:
    if periods < 0:
        raise ValueError("periods must be non-negative")
    if rate <= -1:
        raise ValueError("discount rate must be greater than -100%")
    return value / ((1.0 + rate) ** periods)


def gordon_terminal_value(next_cash_flow: float, discount_rate: float, perpetual_growth: float) -> float:
    if discount_rate <= perpetual_growth:
        raise ValueError("terminal discount rate must exceed perpetual growth")
    return next_cash_flow / (discount_rate - perpetual_growth)


def dcf(cash_flows: Sequence[float], discount_rate: float, perpetual_growth: float) -> DcfResult:
    if not cash_flows:
        raise ValueError("at least one explicit cash flow is required")
    if not all(isfinite(x) for x in cash_flows):
        raise ValueError("cash flows must be finite")
    pv_explicit = sum(present_value(cf, discount_rate, year) for year, cf in enumerate(cash_flows, start=1))
    terminal_cf = cash_flows[-1] * (1.0 + perpetual_growth)
    terminal_value = gordon_terminal_value(terminal_cf, discount_rate, perpetual_growth)
    pv_terminal = present_value(terminal_value, discount_rate, len(cash_flows))
    return DcfResult(pv_explicit + pv_terminal, pv_explicit, pv_terminal, terminal_value)


@dataclass(frozen=True)
class SolveResult:
    value: float | None
    residual: float | None
    iterations: int
    converged: bool
    lower_bound: float
    upper_bound: float


def bounded_bisection(
    objective: Callable[[float], float],
    lower: float,
    upper: float,
    *,
    tolerance: float = 1e-8,
    max_iterations: int = 200,
) -> SolveResult:
    """Solve objective(x)=0 with a bounded, auditable bisection method."""
    if lower >= upper:
        raise ValueError("lower bound must be below upper bound")
    f_low, f_high = objective(lower), objective(upper)
    if not (isfinite(f_low) and isfinite(f_high)):
        raise ValueError("objective must be finite at both bounds")
    if f_low == 0:
        return SolveResult(lower, 0.0, 0, True, lower, upper)
    if f_high == 0:
        return SolveResult(upper, 0.0, 0, True, lower, upper)
    if f_low * f_high > 0:
        return SolveResult(None, None, 0, False, lower, upper)

    lo, hi = lower, upper
    for iteration in range(1, max_iterations + 1):
        mid = (lo + hi) / 2.0
        f_mid = objective(mid)
        if not isfinite(f_mid):
            raise ValueError("objective became non-finite")
        if abs(f_mid) <= tolerance or (hi - lo) / 2.0 <= tolerance:
            return SolveResult(mid, f_mid, iteration, True, lower, upper)
        if f_low * f_mid <= 0:
            hi = mid
            f_high = f_mid
        else:
            lo = mid
            f_low = f_mid
    mid = (lo + hi) / 2.0
    return SolveResult(mid, objective(mid), max_iterations, False, lower, upper)
