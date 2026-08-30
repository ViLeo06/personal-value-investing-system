"""Capital-intensive manufacturing valuation wrapper."""
from __future__ import annotations

from dataclasses import dataclass

from .fcff import (
    ValueDriverFcffAssumptions,
    ValueDriverFcffResult,
    equity_value_per_share,
    value_driver_fcff,
)


@dataclass(frozen=True)
class ManufacturingScenarioAssumptions:
    operating: ValueDriverFcffAssumptions
    cash_and_investments: float
    debt: float
    minority_interest: float
    other_non_operating_assets: float
    shares_outstanding: float


@dataclass(frozen=True)
class ManufacturingScenarioResult:
    operating_result: ValueDriverFcffResult
    intrinsic_value_per_share: float
    explicit_average_ronic: float
    terminal_value_share: float
    terminal_ronic_spread: float


def value_manufacturing_scenario(
    assumptions: ManufacturingScenarioAssumptions,
) -> ManufacturingScenarioResult:
    operating_result = value_driver_fcff(assumptions.operating)
    per_share = equity_value_per_share(
        operating_result.enterprise_value,
        cash_and_investments=assumptions.cash_and_investments,
        debt=assumptions.debt,
        minority_interest=assumptions.minority_interest,
        other_non_operating_assets=assumptions.other_non_operating_assets,
        shares_outstanding=assumptions.shares_outstanding,
    )
    return ManufacturingScenarioResult(
        operating_result=operating_result,
        intrinsic_value_per_share=per_share,
        explicit_average_ronic=sum(assumptions.operating.ronic)
        / len(assumptions.operating.ronic),
        terminal_value_share=operating_result.terminal_value_share,
        terminal_ronic_spread=assumptions.operating.terminal_ronic
        - assumptions.operating.wacc,
    )
