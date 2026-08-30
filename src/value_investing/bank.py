"""Bank scenario wrapper around residual-income valuation."""
from __future__ import annotations

from dataclasses import dataclass

from .residual_income import (
    ResidualIncomeAssumptions,
    ResidualIncomeResult,
    value_residual_income,
)


@dataclass(frozen=True)
class BankOperatingDiagnostics:
    net_interest_margin: float | None = None
    credit_cost: float | None = None
    cost_income_ratio: float | None = None
    common_equity_tier1_ratio: float | None = None
    non_performing_loan_ratio: float | None = None


@dataclass(frozen=True)
class BankScenarioAssumptions:
    residual_income: ResidualIncomeAssumptions
    diagnostics: BankOperatingDiagnostics
    other_equity_claims_per_share: float = 0.0


@dataclass(frozen=True)
class BankScenarioResult:
    residual_income_result: ResidualIncomeResult
    intrinsic_common_value_per_share: float
    price_to_book_value: float
    terminal_value_share: float


def value_bank_scenario(assumptions: BankScenarioAssumptions) -> BankScenarioResult:
    if assumptions.other_equity_claims_per_share < 0:
        raise ValueError("other equity claims per share cannot be negative")
    result = value_residual_income(assumptions.residual_income)
    common_value = (
        result.intrinsic_value_per_share - assumptions.other_equity_claims_per_share
    )
    if common_value < 0:
        raise ValueError("other equity claims exceed residual-income value")
    return BankScenarioResult(
        residual_income_result=result,
        intrinsic_common_value_per_share=common_value,
        price_to_book_value=common_value
        / assumptions.residual_income.opening_book_value_per_share,
        terminal_value_share=result.terminal_value_share,
    )
