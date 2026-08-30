"""Five-year investor-return helpers for residual-income valuations."""
from __future__ import annotations

from math import isfinite
from typing import Sequence

from .residual_income import ResidualIncomeAssumptions, ResidualIncomeResult
from .valuation import SolveResult, bounded_bisection, present_value


def residual_income_holding_value(
    result: ResidualIncomeResult,
    assumptions: ResidualIncomeAssumptions,
    *,
    holding_years: int = 5,
) -> float:
    """Value remaining equity at the holding-period exit date.

    At year five this equals closing book value plus residual income from years
    six onward, all measured at the year-five date. It uses the exact same
    forward residual-income model rather than a separate exit multiple.
    """
    if not 1 <= holding_years < len(result.forecast):
        raise ValueError("holding years must fall inside the explicit forecast")
    closing_book = result.forecast[
        holding_years - 1
    ].closing_book_value_per_share
    continuing_residual_income = sum(
        present_value(
            row.residual_income_per_share,
            assumptions.cost_of_equity,
            row.year - holding_years,
        )
        for row in result.forecast[holding_years:]
    )
    terminal = present_value(
        result.terminal_residual_income_value,
        assumptions.cost_of_equity,
        len(result.forecast) - holding_years,
    )
    return closing_book + continuing_residual_income + terminal


def residual_income_investor_cash_flows(
    current_price: float,
    result: ResidualIncomeResult,
    assumptions: ResidualIncomeAssumptions,
    *,
    holding_years: int = 5,
) -> tuple[float, ...]:
    """Build purchase, dividends and year-five exit value for an investor."""
    if current_price <= 0 or not isfinite(current_price):
        raise ValueError("current price must be finite and positive")
    if not 1 <= holding_years <= len(result.forecast):
        raise ValueError("holding years exceed the explicit forecast")
    exit_value = residual_income_holding_value(
        result, assumptions, holding_years=holding_years
    )
    flows = [-current_price]
    flows.extend(
        row.dividend_per_share for row in result.forecast[: holding_years - 1]
    )
    flows.append(
        result.forecast[holding_years - 1].dividend_per_share + exit_value
    )
    return tuple(flows)


def _npv(rate: float, cash_flows: Sequence[float]) -> float:
    if rate <= -1:
        raise ValueError("IRR rate must be greater than -100%")
    return sum(
        cash_flow / ((1.0 + rate) ** period)
        for period, cash_flow in enumerate(cash_flows)
    )


def residual_income_economic_irr(
    current_price: float,
    result: ResidualIncomeResult,
    assumptions: ResidualIncomeAssumptions,
    *,
    holding_years: int = 5,
) -> SolveResult:
    """Solve the investor's annualized return from dividends and exit value."""
    flows = residual_income_investor_cash_flows(
        current_price, result, assumptions, holding_years=holding_years
    )
    return bounded_bisection(
        lambda rate: _npv(rate, flows),
        -0.999999,
        10.0,
        tolerance=1e-12,
    )


def residual_income_target_buy_price(
    result: ResidualIncomeResult,
    assumptions: ResidualIncomeAssumptions,
    target_return: float = 0.15,
    *,
    holding_years: int = 5,
) -> float:
    """Price today that makes the modeled five-year return equal the hurdle."""
    if target_return <= -1:
        raise ValueError("target return must be greater than -100%")
    future_flows = residual_income_investor_cash_flows(
        1.0, result, assumptions, holding_years=holding_years
    )[1:]
    return sum(
        present_value(value, target_return, year)
        for year, value in enumerate(future_flows, start=1)
    )
