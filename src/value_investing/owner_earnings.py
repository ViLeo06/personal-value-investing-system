"""Owner Earnings DCF model used for high-moat consumer companies.

The implementation mirrors the transparent V1.1 workbook structure:
- years 1-5 use a constant scenario growth rate;
- years 6-10 linearly fade to the perpetual growth rate;
- terminal value is calculated at year 10;
- year-5 economic value is the value, at year 5, of years 6 onward.
"""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite
from typing import Sequence

from .valuation import SolveResult, bounded_bisection, gordon_terminal_value, present_value


@dataclass(frozen=True)
class OwnerEarningsAssumptions:
    starting_owner_earnings_per_share: float
    first_five_year_growth: float
    discount_rate: float
    perpetual_growth: float
    explicit_years: int = 10
    fade_start_year: int = 6

    def validate(self) -> None:
        values = (
            self.starting_owner_earnings_per_share,
            self.first_five_year_growth,
            self.discount_rate,
            self.perpetual_growth,
        )
        if not all(isfinite(v) for v in values):
            raise ValueError("assumptions must be finite")
        if self.starting_owner_earnings_per_share < 0:
            raise ValueError("starting owner earnings must be non-negative")
        if self.explicit_years < 2:
            raise ValueError("explicit_years must be at least 2")
        if not 2 <= self.fade_start_year <= self.explicit_years:
            raise ValueError("fade_start_year must fall inside the explicit forecast")
        if self.discount_rate <= self.perpetual_growth:
            raise ValueError("discount rate must exceed perpetual growth")
        if self.discount_rate <= -1 or self.first_five_year_growth <= -1 or self.perpetual_growth <= -1:
            raise ValueError("rates must be greater than -100%")


@dataclass(frozen=True)
class OwnerEarningsResult:
    growth_rates: tuple[float, ...]
    owner_earnings: tuple[float, ...]
    present_values: tuple[float, ...]
    terminal_value_at_horizon: float
    present_value_terminal: float
    intrinsic_value_per_share: float
    year_five_value_per_share: float
    terminal_value_share: float


def growth_path(assumptions: OwnerEarningsAssumptions) -> tuple[float, ...]:
    assumptions.validate()
    stable_years = assumptions.fade_start_year - 1
    fade_years = assumptions.explicit_years - stable_years
    rates: list[float] = []
    for year in range(1, assumptions.explicit_years + 1):
        if year <= stable_years:
            rate = assumptions.first_five_year_growth
        else:
            step = year - stable_years
            rate = assumptions.first_five_year_growth + (
                assumptions.perpetual_growth - assumptions.first_five_year_growth
            ) * step / fade_years
        rates.append(rate)
    return tuple(rates)


def project_owner_earnings(assumptions: OwnerEarningsAssumptions) -> tuple[float, ...]:
    earnings: list[float] = []
    current = assumptions.starting_owner_earnings_per_share
    for rate in growth_path(assumptions):
        current *= 1.0 + rate
        earnings.append(current)
    return tuple(earnings)


def value_owner_earnings(assumptions: OwnerEarningsAssumptions) -> OwnerEarningsResult:
    earnings = project_owner_earnings(assumptions)
    rates = growth_path(assumptions)
    pvs = tuple(
        present_value(value, assumptions.discount_rate, year)
        for year, value in enumerate(earnings, start=1)
    )
    terminal_value = gordon_terminal_value(
        earnings[-1] * (1.0 + assumptions.perpetual_growth),
        assumptions.discount_rate,
        assumptions.perpetual_growth,
    )
    pv_terminal = present_value(terminal_value, assumptions.discount_rate, assumptions.explicit_years)
    intrinsic_value = sum(pvs) + pv_terminal

    # Value at the end of year 5, matching the V1.1 workbook convention.
    year_five_index = 5
    if assumptions.explicit_years < year_five_index:
        raise ValueError("owner-earnings model requires at least five explicit years")
    year_five_value = sum(
        present_value(earnings[index], assumptions.discount_rate, index + 1 - year_five_index)
        for index in range(year_five_index, assumptions.explicit_years)
    ) + present_value(
        terminal_value,
        assumptions.discount_rate,
        assumptions.explicit_years - year_five_index,
    )
    terminal_share = pv_terminal / intrinsic_value if intrinsic_value else 0.0
    return OwnerEarningsResult(
        growth_rates=rates,
        owner_earnings=earnings,
        present_values=pvs,
        terminal_value_at_horizon=terminal_value,
        present_value_terminal=pv_terminal,
        intrinsic_value_per_share=intrinsic_value,
        year_five_value_per_share=year_five_value,
        terminal_value_share=terminal_share,
    )


def cash_flows_to_investor(
    current_price: float,
    result: OwnerEarningsResult,
    *,
    holding_years: int = 5,
) -> tuple[float, ...]:
    if current_price <= 0:
        raise ValueError("current price must be positive")
    if holding_years != 5:
        raise ValueError("V1.2 owner-earnings convention currently supports five-year holding periods")
    flows = [-current_price]
    flows.extend(result.owner_earnings[: holding_years - 1])
    flows.append(result.owner_earnings[holding_years - 1] + result.year_five_value_per_share)
    return tuple(flows)


def _npv(rate: float, cash_flows: Sequence[float]) -> float:
    if rate <= -1:
        raise ValueError("IRR rate must be greater than -100%")
    return sum(cf / ((1.0 + rate) ** period) for period, cf in enumerate(cash_flows))


def economic_irr(current_price: float, result: OwnerEarningsResult) -> SolveResult:
    flows = cash_flows_to_investor(current_price, result)
    return bounded_bisection(lambda rate: _npv(rate, flows), -0.999999, 10.0, tolerance=1e-12)


def target_buy_price(result: OwnerEarningsResult, target_return: float = 0.15) -> float:
    if target_return <= -1:
        raise ValueError("target return must be greater than -100%")
    five_year_flows = list(result.owner_earnings[:5])
    five_year_flows[-1] += result.year_five_value_per_share
    return sum(
        present_value(value, target_return, year)
        for year, value in enumerate(five_year_flows, start=1)
    )


def implied_first_five_year_growth(
    target_price: float,
    template: OwnerEarningsAssumptions,
    *,
    lower_bound: float = -0.50,
    upper_bound: float = 0.50,
) -> SolveResult:
    if target_price <= 0:
        raise ValueError("target price must be positive")

    def objective(growth: float) -> float:
        assumptions = OwnerEarningsAssumptions(
            starting_owner_earnings_per_share=template.starting_owner_earnings_per_share,
            first_five_year_growth=growth,
            discount_rate=template.discount_rate,
            perpetual_growth=template.perpetual_growth,
            explicit_years=template.explicit_years,
            fade_start_year=template.fade_start_year,
        )
        return value_owner_earnings(assumptions).intrinsic_value_per_share - target_price

    return bounded_bisection(objective, lower_bound, upper_bound, tolerance=1e-12)
