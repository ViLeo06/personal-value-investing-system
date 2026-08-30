"""Platform-technology valuation composed from operating FCFF and SOTP."""
from __future__ import annotations

from dataclasses import dataclass

from .fcff import ValueDriverFcffAssumptions, ValueDriverFcffResult, value_driver_fcff
from .sotp import SotPComponent, SotPResult, sum_of_the_parts


@dataclass(frozen=True)
class PlatformScenarioAssumptions:
    operating: ValueDriverFcffAssumptions
    investment_components: tuple[SotPComponent, ...]
    non_operating_assets: float
    debt: float
    minority_interest: float
    other_claims: float
    shares_outstanding: float


@dataclass(frozen=True)
class PlatformScenarioResult:
    operating_result: ValueDriverFcffResult
    sotp_result: SotPResult
    operating_value_share: float
    investment_value_share: float
    bridge_value_share: float

    @property
    def intrinsic_value_per_share(self) -> float:
        return self.sotp_result.value_per_share


def value_platform_scenario(
    assumptions: PlatformScenarioAssumptions,
) -> PlatformScenarioResult:
    operating_result = value_driver_fcff(assumptions.operating)
    operating_component = SotPComponent(
        "operating_business", operating_result.enterprise_value
    )
    components = (operating_component,) + assumptions.investment_components
    sotp = sum_of_the_parts(
        components,
        non_operating_assets=assumptions.non_operating_assets,
        debt=assumptions.debt,
        minority_interest=assumptions.minority_interest,
        other_claims=assumptions.other_claims,
        shares_outstanding=assumptions.shares_outstanding,
    )
    investment_value = sum(
        component.attributable_value for component in assumptions.investment_components
    )
    bridge_value = (
        assumptions.non_operating_assets
        - assumptions.debt
        - assumptions.minority_interest
        - assumptions.other_claims
    )
    return PlatformScenarioResult(
        operating_result=operating_result,
        sotp_result=sotp,
        operating_value_share=operating_result.enterprise_value
        / assumptions.shares_outstanding,
        investment_value_share=investment_value / assumptions.shares_outstanding,
        bridge_value_share=bridge_value / assumptions.shares_outstanding,
    )
