from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Sequence


@dataclass(frozen=True, slots=True)
class DcfResult:
    present_value_explicit: float
    present_value_terminal: float
    enterprise_value: float
    terminal_value_share: float


def dcf_from_cash_flows(
    cash_flows: Sequence[float],
    *,
    discount_rate: float,
    terminal_growth: float,
    terminal_cash_flow: float | None = None,
) -> DcfResult:
    if not cash_flows:
        raise ValueError("cash_flows cannot be empty")
    if discount_rate <= terminal_growth:
        raise ValueError("discount_rate must exceed terminal_growth")
    if discount_rate <= -1:
        raise ValueError("discount_rate must be greater than -100%")
    explicit = sum(
        cash_flow / ((1.0 + discount_rate) ** year)
        for year, cash_flow in enumerate(cash_flows, 1)
    )
    final_cash_flow = cash_flows[-1] if terminal_cash_flow is None else terminal_cash_flow
    terminal_value = final_cash_flow * (1.0 + terminal_growth) / (
        discount_rate - terminal_growth
    )
    pv_terminal = terminal_value / ((1.0 + discount_rate) ** len(cash_flows))
    enterprise_value = explicit + pv_terminal
    return DcfResult(
        present_value_explicit=explicit,
        present_value_terminal=pv_terminal,
        enterprise_value=enterprise_value,
        terminal_value_share=pv_terminal / enterprise_value,
    )


def bounded_bisection(
    function: Callable[[float], float],
    lower: float,
    upper: float,
    *,
    tolerance: float = 1e-10,
    max_iterations: int = 250,
) -> float:
    if lower >= upper:
        raise ValueError("lower must be smaller than upper")
    f_lower = function(lower)
    f_upper = function(upper)
    if f_lower == 0:
        return lower
    if f_upper == 0:
        return upper
    if f_lower * f_upper > 0:
        raise ValueError("Root is not bracketed")
    for _ in range(max_iterations):
        midpoint = (lower + upper) / 2.0
        f_midpoint = function(midpoint)
        if abs(f_midpoint) <= tolerance or (upper - lower) / 2.0 <= tolerance:
            return midpoint
        if f_lower * f_midpoint <= 0:
            upper = midpoint
        else:
            lower = midpoint
            f_lower = f_midpoint
    raise RuntimeError("Bisection did not converge")
