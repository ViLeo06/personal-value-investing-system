"""Deterministic value-driver FCFF primitives.

The module forecasts operating results from revenue, margins and incremental
returns on new capital. It does not fetch data or decide company-specific
assumptions.
"""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite
from typing import Sequence

from .valuation import present_value


@dataclass(frozen=True)
class FcffYear:
    year: int
    revenue: float
    operating_margin: float
    ebit: float
    nopat: float
    incremental_nopat: float
    ronic: float
    reinvestment: float
    fcff: float
    discount_factor: float
    present_value: float


@dataclass(frozen=True)
class ValueDriverFcffAssumptions:
    starting_revenue: float
    starting_operating_margin: float
    tax_rate: float
    revenue_growth: Sequence[float]
    operating_margins: Sequence[float]
    ronic: Sequence[float]
    wacc: float
    terminal_growth: float
    terminal_ronic: float


@dataclass(frozen=True)
class ValueDriverFcffResult:
    enterprise_value: float
    pv_explicit_fcff: float
    pv_terminal_value: float
    terminal_value: float
    terminal_fcff: float
    terminal_value_share: float
    forecast: tuple[FcffYear, ...]


def _validate(assumptions: ValueDriverFcffAssumptions) -> None:
    lengths = {
        len(assumptions.revenue_growth),
        len(assumptions.operating_margins),
        len(assumptions.ronic),
    }
    if len(lengths) != 1 or not assumptions.revenue_growth:
        raise ValueError("growth, margin and RONIC paths must have one equal non-zero length")
    scalar_values = (
        assumptions.starting_revenue,
        assumptions.starting_operating_margin,
        assumptions.tax_rate,
        assumptions.wacc,
        assumptions.terminal_growth,
        assumptions.terminal_ronic,
    )
    path_values = tuple(assumptions.revenue_growth) + tuple(assumptions.operating_margins) + tuple(assumptions.ronic)
    if not all(isfinite(value) for value in scalar_values + path_values):
        raise ValueError("all assumptions must be finite")
    if assumptions.starting_revenue <= 0:
        raise ValueError("starting revenue must be positive")
    if not 0 <= assumptions.tax_rate < 1:
        raise ValueError("tax rate must be in [0, 1)")
    if assumptions.wacc <= assumptions.terminal_growth:
        raise ValueError("WACC must exceed terminal growth")
    if assumptions.terminal_ronic <= 0:
        raise ValueError("terminal RONIC must be positive")
    if assumptions.terminal_growth < 0:
        raise ValueError("terminal growth must be non-negative")
    if assumptions.terminal_growth > assumptions.terminal_ronic:
        raise ValueError("terminal growth cannot exceed terminal RONIC")
    if any(growth <= -1 for growth in assumptions.revenue_growth):
        raise ValueError("revenue growth must exceed -100%")
    if any(ronic <= 0 for ronic in assumptions.ronic):
        raise ValueError("explicit RONIC must be positive")


def value_driver_fcff(assumptions: ValueDriverFcffAssumptions) -> ValueDriverFcffResult:
    """Value operations using incremental NOPAT / RONIC reinvestment.

    Reinvestment is allowed to be negative when NOPAT contracts, representing a
    release of capital. Company-specific normalization may cap that release
    before calling this function if required.
    """
    _validate(assumptions)
    prior_revenue = assumptions.starting_revenue
    prior_nopat = (
        assumptions.starting_revenue
        * assumptions.starting_operating_margin
        * (1.0 - assumptions.tax_rate)
    )
    forecast: list[FcffYear] = []
    pv_explicit = 0.0

    for index, (growth, margin, ronic) in enumerate(
        zip(
            assumptions.revenue_growth,
            assumptions.operating_margins,
            assumptions.ronic,
            strict=True,
        ),
        start=1,
    ):
        revenue = prior_revenue * (1.0 + growth)
        ebit = revenue * margin
        nopat = ebit * (1.0 - assumptions.tax_rate)
        incremental_nopat = nopat - prior_nopat
        reinvestment = incremental_nopat / ronic
        fcff = nopat - reinvestment
        discount_factor = (1.0 + assumptions.wacc) ** index
        pv = fcff / discount_factor
        forecast.append(
            FcffYear(
                year=index,
                revenue=revenue,
                operating_margin=margin,
                ebit=ebit,
                nopat=nopat,
                incremental_nopat=incremental_nopat,
                ronic=ronic,
                reinvestment=reinvestment,
                fcff=fcff,
                discount_factor=discount_factor,
                present_value=pv,
            )
        )
        pv_explicit += pv
        prior_revenue = revenue
        prior_nopat = nopat

    next_nopat = prior_nopat * (1.0 + assumptions.terminal_growth)
    terminal_reinvestment_rate = assumptions.terminal_growth / assumptions.terminal_ronic
    terminal_fcff = next_nopat * (1.0 - terminal_reinvestment_rate)
    terminal_value = terminal_fcff / (assumptions.wacc - assumptions.terminal_growth)
    pv_terminal = present_value(terminal_value, assumptions.wacc, len(forecast))
    enterprise_value = pv_explicit + pv_terminal
    return ValueDriverFcffResult(
        enterprise_value=enterprise_value,
        pv_explicit_fcff=pv_explicit,
        pv_terminal_value=pv_terminal,
        terminal_value=terminal_value,
        terminal_fcff=terminal_fcff,
        terminal_value_share=pv_terminal / enterprise_value,
        forecast=tuple(forecast),
    )


def equity_value_per_share(
    enterprise_value: float,
    *,
    cash_and_investments: float,
    debt: float,
    minority_interest: float = 0.0,
    other_non_operating_assets: float = 0.0,
    shares_outstanding: float,
) -> float:
    values = (
        enterprise_value,
        cash_and_investments,
        debt,
        minority_interest,
        other_non_operating_assets,
        shares_outstanding,
    )
    if not all(isfinite(value) for value in values):
        raise ValueError("equity bridge values must be finite")
    if shares_outstanding <= 0:
        raise ValueError("shares outstanding must be positive")
    equity_value = (
        enterprise_value
        + cash_and_investments
        + other_non_operating_assets
        - debt
        - minority_interest
    )
    return equity_value / shares_outstanding
