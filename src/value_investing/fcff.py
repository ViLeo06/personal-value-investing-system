"""Deterministic FCFF primitives and a platform FCFF valuation model.

Two related APIs live here:

* ``value_driver_fcff`` accepts fully explicit revenue, margin and RONIC paths.
  It is the low-level operating engine used by platform/SOTP compositions.
* ``value_fcff`` accepts a compact scenario definition compatible with the
  original V1.2 model-family contract. It expands that definition into an
  auditable path, bridges enterprise value to equity value, and supports the
  five-year decision and reverse-DCF helpers.

Neither API fetches data or chooses company-specific assumptions.
"""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite
from typing import Sequence

from .valuation import (
    SolveResult,
    bounded_bisection,
    gordon_terminal_value,
    present_value,
)


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
    path_values = (
        tuple(assumptions.revenue_growth)
        + tuple(assumptions.operating_margins)
        + tuple(assumptions.ronic)
    )
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
    """Value operations using incremental NOPAT / RONIC reinvestment."""
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


@dataclass(frozen=True)
class FcffAssumptions:
    """Compact FCFF scenario used by the ``fcff_sotp`` model family."""

    starting_revenue: float
    first_five_year_revenue_growth: float
    starting_operating_margin: float
    target_operating_margin: float
    tax_rate: float
    sales_to_capital: float
    discount_rate: float
    perpetual_growth: float
    terminal_ronic: float
    non_operating_assets: float = 0.0
    net_debt: float = 0.0
    shares_outstanding: float = 1.0
    explicit_years: int = 10
    fade_start_year: int = 6

    def validate(self) -> None:
        values = (
            self.starting_revenue,
            self.first_five_year_revenue_growth,
            self.starting_operating_margin,
            self.target_operating_margin,
            self.tax_rate,
            self.sales_to_capital,
            self.discount_rate,
            self.perpetual_growth,
            self.terminal_ronic,
            self.non_operating_assets,
            self.net_debt,
            self.shares_outstanding,
        )
        if not all(isfinite(value) for value in values):
            raise ValueError("all assumptions must be finite")
        if self.starting_revenue <= 0:
            raise ValueError("starting_revenue must be positive")
        if self.first_five_year_revenue_growth <= -1:
            raise ValueError("revenue growth must be greater than -100%")
        if not 0 <= self.tax_rate < 1:
            raise ValueError("tax_rate must be in [0, 1)")
        if self.sales_to_capital <= 0:
            raise ValueError("sales_to_capital must be positive")
        if self.discount_rate <= self.perpetual_growth:
            raise ValueError("discount_rate must exceed perpetual_growth")
        if self.terminal_ronic <= self.perpetual_growth:
            raise ValueError("terminal_ronic must exceed perpetual_growth")
        if self.shares_outstanding <= 0:
            raise ValueError("shares_outstanding must be positive")
        if self.explicit_years < 5:
            raise ValueError("explicit_years must be at least five")
        if not 2 <= self.fade_start_year <= self.explicit_years:
            raise ValueError("fade_start_year must fall inside the explicit forecast")


@dataclass(frozen=True)
class FcffResult:
    years: tuple[FcffYear, ...]
    terminal_fcff: float
    terminal_value: float
    operating_enterprise_value: float
    equity_value: float
    intrinsic_value_per_share: float
    year_five_equity_value_per_share: float
    terminal_value_share: float


def _linear_fade(
    initial: float,
    terminal: float,
    year: int,
    *,
    explicit_years: int,
    fade_start_year: int,
) -> float:
    stable_years = fade_start_year - 1
    if year <= stable_years:
        return initial
    fade_years = explicit_years - stable_years
    return initial + (terminal - initial) * (year - stable_years) / fade_years


def _operating_margin_path(assumptions: FcffAssumptions, year: int) -> float:
    transition_years = min(5, assumptions.explicit_years)
    progress = min(year, transition_years) / transition_years
    return assumptions.starting_operating_margin + (
        assumptions.target_operating_margin - assumptions.starting_operating_margin
    ) * progress


def value_fcff(assumptions: FcffAssumptions) -> FcffResult:
    """Value a compact revenue/margin FCFF scenario and bridge to equity."""

    assumptions.validate()
    previous_revenue = assumptions.starting_revenue
    previous_nopat = (
        previous_revenue
        * assumptions.starting_operating_margin
        * (1.0 - assumptions.tax_rate)
    )
    years: list[FcffYear] = []
    pv_explicit = 0.0

    for year in range(1, assumptions.explicit_years + 1):
        growth = _linear_fade(
            assumptions.first_five_year_revenue_growth,
            assumptions.perpetual_growth,
            year,
            explicit_years=assumptions.explicit_years,
            fade_start_year=assumptions.fade_start_year,
        )
        margin = _operating_margin_path(assumptions, year)
        revenue = previous_revenue * (1.0 + growth)
        ebit = revenue * margin
        nopat = ebit * (1.0 - assumptions.tax_rate)
        incremental_nopat = nopat - previous_nopat
        reinvestment = (revenue - previous_revenue) / assumptions.sales_to_capital
        implied_ronic = (
            incremental_nopat / reinvestment
            if abs(reinvestment) > 1e-15
            else assumptions.terminal_ronic
        )
        fcff = nopat - reinvestment
        discount_factor = (1.0 + assumptions.discount_rate) ** year
        pv = fcff / discount_factor
        years.append(
            FcffYear(
                year=year,
                revenue=revenue,
                operating_margin=margin,
                ebit=ebit,
                nopat=nopat,
                incremental_nopat=incremental_nopat,
                ronic=implied_ronic,
                reinvestment=reinvestment,
                fcff=fcff,
                discount_factor=discount_factor,
                present_value=pv,
            )
        )
        pv_explicit += pv
        previous_revenue = revenue
        previous_nopat = nopat

    next_revenue = previous_revenue * (1.0 + assumptions.perpetual_growth)
    next_nopat = (
        next_revenue
        * assumptions.target_operating_margin
        * (1.0 - assumptions.tax_rate)
    )
    terminal_reinvestment_rate = assumptions.perpetual_growth / assumptions.terminal_ronic
    terminal_fcff = next_nopat * (1.0 - terminal_reinvestment_rate)
    terminal_value = gordon_terminal_value(
        terminal_fcff,
        assumptions.discount_rate,
        assumptions.perpetual_growth,
    )
    pv_terminal = present_value(
        terminal_value,
        assumptions.discount_rate,
        assumptions.explicit_years,
    )
    operating_value = pv_explicit + pv_terminal
    equity_value = (
        operating_value + assumptions.non_operating_assets - assumptions.net_debt
    )

    holding_year = 5
    operating_value_at_five = sum(
        present_value(row.fcff, assumptions.discount_rate, row.year - holding_year)
        for row in years[holding_year:]
    ) + present_value(
        terminal_value,
        assumptions.discount_rate,
        assumptions.explicit_years - holding_year,
    )
    year_five_equity_value = (
        operating_value_at_five
        + assumptions.non_operating_assets
        - assumptions.net_debt
    )
    return FcffResult(
        years=tuple(years),
        terminal_fcff=terminal_fcff,
        terminal_value=terminal_value,
        operating_enterprise_value=operating_value,
        equity_value=equity_value,
        intrinsic_value_per_share=equity_value / assumptions.shares_outstanding,
        year_five_equity_value_per_share=(
            year_five_equity_value / assumptions.shares_outstanding
        ),
        terminal_value_share=pv_terminal / operating_value if operating_value else 0.0,
    )


def five_year_irr(current_price: float, result: FcffResult) -> float:
    if current_price <= 0:
        raise ValueError("current_price must be positive")
    if result.year_five_equity_value_per_share < 0:
        raise ValueError("year-five equity value cannot be negative")
    return (result.year_five_equity_value_per_share / current_price) ** 0.2 - 1.0


def target_buy_price(result: FcffResult, target_return: float = 0.15) -> float:
    if target_return <= -1:
        raise ValueError("target_return must be greater than -100%")
    return present_value(
        result.year_five_equity_value_per_share,
        target_return,
        5,
    )


def implied_revenue_growth(
    target_price: float,
    template: FcffAssumptions,
    *,
    lower_bound: float = -0.50,
    upper_bound: float = 0.80,
) -> SolveResult:
    if target_price <= 0:
        raise ValueError("target_price must be positive")

    def objective(growth: float) -> float:
        candidate = FcffAssumptions(
            starting_revenue=template.starting_revenue,
            first_five_year_revenue_growth=growth,
            starting_operating_margin=template.starting_operating_margin,
            target_operating_margin=template.target_operating_margin,
            tax_rate=template.tax_rate,
            sales_to_capital=template.sales_to_capital,
            discount_rate=template.discount_rate,
            perpetual_growth=template.perpetual_growth,
            terminal_ronic=template.terminal_ronic,
            non_operating_assets=template.non_operating_assets,
            net_debt=template.net_debt,
            shares_outstanding=template.shares_outstanding,
            explicit_years=template.explicit_years,
            fade_start_year=template.fade_start_year,
        )
        return value_fcff(candidate).intrinsic_value_per_share - target_price

    return bounded_bisection(
        objective,
        lower_bound,
        upper_bound,
        tolerance=1e-11,
    )
