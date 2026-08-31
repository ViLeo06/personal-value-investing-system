"""Compatibility exports for the original V1.2 valuation API."""

from __future__ import annotations

from typing import Sequence

from .core import DcfResult, bounded_bisection, dcf_from_cash_flows


def present_value(value: float, discount_rate: float, period: int) -> float:
    if period < 0:
        raise ValueError("period cannot be negative")
    if discount_rate <= -1:
        raise ValueError("discount_rate must be greater than -100%")
    return value / ((1.0 + discount_rate) ** period)


def gordon_terminal_value(
    last_cash_flow: float,
    discount_rate: float,
    growth_rate: float,
) -> float:
    if discount_rate <= growth_rate:
        raise ValueError("discount_rate must exceed growth_rate")
    return last_cash_flow * (1.0 + growth_rate) / (discount_rate - growth_rate)


def dcf(
    cash_flows: Sequence[float],
    discount_rate: float,
    terminal_growth: float,
    terminal_cash_flow: float | None = None,
) -> DcfResult:
    return dcf_from_cash_flows(
        cash_flows,
        discount_rate=discount_rate,
        terminal_growth=terminal_growth,
        terminal_cash_flow=terminal_cash_flow,
    )


__all__ = [
    "DcfResult",
    "bounded_bisection",
    "dcf",
    "dcf_from_cash_flows",
    "gordon_terminal_value",
    "present_value",
]
