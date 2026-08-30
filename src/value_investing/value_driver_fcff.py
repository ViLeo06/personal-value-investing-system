"""Value-driver FCFF based on NOPAT growth, reinvestment and RONIC.

This is the preferred transparent core for capital-intensive manufacturers. It
makes the identity growth = reinvestment rate × RONIC explicit in every year.
"""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite

from .valuation import SolveResult, bounded_bisection, gordon_terminal_value, present_value


@dataclass(frozen=True)
class ValueDriverAssumptions:
    starting_nopat: float
    first_five_year_growth: float
    starting_ronic: float
    terminal_ronic: float
    discount_rate: float
    perpetual_growth: float
    non_operating_assets: float = 0.0
    net_debt: float = 0.0
    shares_outstanding: float = 1.0
    explicit_years: int = 10
    fade_start_year: int = 6

    def validate(self) -> None:
        values = (
            self.starting_nopat,
            self.first_five_year_growth,
            self.starting_ronic,
            self.terminal_ronic,
            self.discount_rate,
            self.perpetual_growth,
            self.non_operating_assets,
            self.net_debt,
            self.shares_outstanding,
        )
        if not all(isfinite(value) for value in values):
            raise ValueError("all assumptions must be finite")
        if self.starting_nopat < 0:
            raise ValueError("starting_nopat must be non-negative")
        if self.starting_ronic <= 0 or self.terminal_ronic <= 0:
            raise ValueError("RONIC must be positive")
        if self.terminal_ronic <= self.perpetual_growth:
            raise ValueError("terminal RONIC must exceed perpetual growth")
        if self.discount_rate <= self.perpetual_growth:
            raise ValueError("discount rate must exceed perpetual growth")
        if self.shares_outstanding <= 0:
            raise ValueError("shares_outstanding must be positive")
        if self.explicit_years < 5:
            raise ValueError("explicit_years must be at least five")
        if not 2 <= self.fade_start_year <= self.explicit_years:
            raise ValueError("fade_start_year must fall inside the explicit forecast")
        if self.first_five_year_growth <= -1 or self.perpetual_growth <= -1:
            raise ValueError("growth rates must be greater than -100%")


@dataclass(frozen=True)
class ValueDriverYear:
    year: int
    growth: float
    ronic: float
    nopat: float
    reinvestment_rate: float
    reinvestment: float
    fcff: float


@dataclass(frozen=True)
class ValueDriverResult:
    years: tuple[ValueDriverYear, ...]
    terminal_fcff: float
    terminal_value: float
    operating_enterprise_value: float
    equity_value: float
    intrinsic_value_per_share: float
    year_five_equity_value_per_share: float
    terminal_value_share: float


def _fade(
    initial: float,
    terminal: float,
    year: int,
    explicit_years: int,
    fade_start_year: int,
) -> float:
    stable_years = fade_start_year - 1
    if year <= stable_years:
        return initial
    fade_years = explicit_years - stable_years
    return initial + (terminal - initial) * (year - stable_years) / fade_years


def project_value_driver(
    assumptions: ValueDriverAssumptions,
) -> tuple[ValueDriverYear, ...]:
    assumptions.validate()
    previous_nopat = assumptions.starting_nopat
    rows: list[ValueDriverYear] = []
    for year in range(1, assumptions.explicit_years + 1):
        growth = _fade(
            assumptions.first_five_year_growth,
            assumptions.perpetual_growth,
            year,
            assumptions.explicit_years,
            assumptions.fade_start_year,
        )
        ronic = _fade(
            assumptions.starting_ronic,
            assumptions.terminal_ronic,
            year,
            assumptions.explicit_years,
            assumptions.fade_start_year,
        )
        if growth > ronic:
            raise ValueError(
                "growth cannot exceed RONIC because reinvestment rate would exceed 100%"
            )
        nopat = previous_nopat * (1.0 + growth)
        reinvestment_rate = growth / ronic
        reinvestment = previous_nopat * reinvestment_rate
        fcff = nopat - reinvestment
        rows.append(
            ValueDriverYear(
                year=year,
                growth=growth,
                ronic=ronic,
                nopat=nopat,
                reinvestment_rate=reinvestment_rate,
                reinvestment=reinvestment,
                fcff=fcff,
            )
        )
        previous_nopat = nopat
    return tuple(rows)


def value_value_driver(
    assumptions: ValueDriverAssumptions,
) -> ValueDriverResult:
    rows = project_value_driver(assumptions)
    pv_explicit = sum(
        present_value(row.fcff, assumptions.discount_rate, row.year) for row in rows
    )
    next_nopat = rows[-1].nopat * (1.0 + assumptions.perpetual_growth)
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
    future_at_five = sum(
        present_value(row.fcff, assumptions.discount_rate, row.year - holding_year)
        for row in rows[holding_year:]
    ) + present_value(
        terminal_value,
        assumptions.discount_rate,
        assumptions.explicit_years - holding_year,
    )
    year_five_equity = (
        future_at_five + assumptions.non_operating_assets - assumptions.net_debt
    )
    return ValueDriverResult(
        years=rows,
        terminal_fcff=terminal_fcff,
        terminal_value=terminal_value,
        operating_enterprise_value=operating_value,
        equity_value=equity_value,
        intrinsic_value_per_share=equity_value / assumptions.shares_outstanding,
        year_five_equity_value_per_share=(
            year_five_equity / assumptions.shares_outstanding
        ),
        terminal_value_share=(
            pv_terminal / operating_value if operating_value else 0.0
        ),
    )


def five_year_irr(current_price: float, result: ValueDriverResult) -> float:
    if current_price <= 0:
        raise ValueError("current_price must be positive")
    if result.year_five_equity_value_per_share < 0:
        raise ValueError("year-five equity value cannot be negative")
    return (result.year_five_equity_value_per_share / current_price) ** 0.2 - 1.0


def target_buy_price(
    result: ValueDriverResult,
    target_return: float = 0.15,
) -> float:
    if target_return <= -1:
        raise ValueError("target_return must be greater than -100%")
    return present_value(
        result.year_five_equity_value_per_share,
        target_return,
        5,
    )


def implied_growth(
    target_price: float,
    template: ValueDriverAssumptions,
    *,
    lower_bound: float = -0.30,
    upper_bound: float | None = None,
) -> SolveResult:
    if target_price <= 0:
        raise ValueError("target_price must be positive")
    upper = (
        upper_bound
        if upper_bound is not None
        else min(0.80, template.starting_ronic * 0.999)
    )

    def objective(growth: float) -> float:
        assumptions = ValueDriverAssumptions(
            starting_nopat=template.starting_nopat,
            first_five_year_growth=growth,
            starting_ronic=template.starting_ronic,
            terminal_ronic=template.terminal_ronic,
            discount_rate=template.discount_rate,
            perpetual_growth=template.perpetual_growth,
            non_operating_assets=template.non_operating_assets,
            net_debt=template.net_debt,
            shares_outstanding=template.shares_outstanding,
            explicit_years=template.explicit_years,
            fade_start_year=template.fade_start_year,
        )
        return value_value_driver(assumptions).intrinsic_value_per_share - target_price

    return bounded_bisection(
        objective,
        lower_bound,
        upper,
        tolerance=1e-11,
    )
