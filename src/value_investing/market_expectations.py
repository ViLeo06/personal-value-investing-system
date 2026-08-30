"""Reverse valuation helpers that reuse the exact forward models."""
from __future__ import annotations

from dataclasses import replace
from math import isfinite

from .fcff import ValueDriverFcffAssumptions, equity_value_per_share, value_driver_fcff
from .residual_income import ResidualIncomeAssumptions, implied_uniform_roe
from .sotp import SotPComponent, sum_of_the_parts
from .valuation import SolveResult, bounded_bisection


def implied_uniform_fcff_growth(
    target_price: float,
    template: ValueDriverFcffAssumptions,
    *,
    cash_and_investments: float,
    debt: float,
    shares_outstanding: float,
    minority_interest: float = 0.0,
    other_non_operating_assets: float = 0.0,
    lower: float = -0.50,
    upper: float = 0.50,
) -> SolveResult:
    if target_price <= 0 or not isfinite(target_price):
        raise ValueError("target price must be finite and positive")

    def objective(growth: float) -> float:
        assumptions = replace(
            template,
            revenue_growth=[growth] * len(template.revenue_growth),
        )
        enterprise_value = value_driver_fcff(assumptions).enterprise_value
        per_share = equity_value_per_share(
            enterprise_value,
            cash_and_investments=cash_and_investments,
            debt=debt,
            minority_interest=minority_interest,
            other_non_operating_assets=other_non_operating_assets,
            shares_outstanding=shares_outstanding,
        )
        return per_share - target_price

    return bounded_bisection(objective, lower, upper)


def implied_platform_operating_growth(
    target_price: float,
    operating_template: ValueDriverFcffAssumptions,
    *,
    investment_components: tuple[SotPComponent, ...],
    non_operating_assets: float,
    debt: float,
    minority_interest: float,
    other_claims: float,
    shares_outstanding: float,
    lower: float = -0.50,
    upper: float = 0.50,
) -> SolveResult:
    """Solve operating revenue growth while holding investment assets fixed."""
    if target_price <= 0 or not isfinite(target_price):
        raise ValueError("target price must be finite and positive")

    def objective(growth: float) -> float:
        assumptions = replace(
            operating_template,
            revenue_growth=[growth] * len(operating_template.revenue_growth),
        )
        operating_value = value_driver_fcff(assumptions).enterprise_value
        result = sum_of_the_parts(
            (SotPComponent("operating_business", operating_value),)
            + investment_components,
            non_operating_assets=non_operating_assets,
            debt=debt,
            minority_interest=minority_interest,
            other_claims=other_claims,
            shares_outstanding=shares_outstanding,
        )
        return result.value_per_share - target_price

    return bounded_bisection(objective, lower, upper)


__all__ = [
    "implied_uniform_fcff_growth",
    "implied_platform_operating_growth",
    "implied_uniform_roe",
]
