"""Transparent sum-of-the-parts valuation helpers."""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite
from typing import Sequence


@dataclass(frozen=True)
class SotPComponent:
    name: str
    gross_value: float
    ownership: float = 1.0
    holding_discount: float = 0.0

    @property
    def attributable_value(self) -> float:
        return self.gross_value * self.ownership * (1.0 - self.holding_discount)


@dataclass(frozen=True)
class SotPResult:
    component_value: float
    non_operating_assets: float
    debt: float
    minority_interest: float
    other_claims: float
    equity_value: float
    value_per_share: float
    components: tuple[SotPComponent, ...]


def sum_of_the_parts(
    components: Sequence[SotPComponent],
    *,
    non_operating_assets: float = 0.0,
    debt: float = 0.0,
    minority_interest: float = 0.0,
    other_claims: float = 0.0,
    shares_outstanding: float,
) -> SotPResult:
    if not components:
        raise ValueError("at least one SOTP component is required")
    if shares_outstanding <= 0 or not isfinite(shares_outstanding):
        raise ValueError("shares outstanding must be finite and positive")
    bridge = (non_operating_assets, debt, minority_interest, other_claims)
    if not all(isfinite(value) for value in bridge):
        raise ValueError("SOTP bridge values must be finite")

    for component in components:
        if not component.name:
            raise ValueError("component name is required")
        if not all(
            isfinite(value)
            for value in (
                component.gross_value,
                component.ownership,
                component.holding_discount,
            )
        ):
            raise ValueError("component values must be finite")
        if not 0 <= component.ownership <= 1:
            raise ValueError("ownership must be in [0, 1]")
        if not 0 <= component.holding_discount < 1:
            raise ValueError("holding discount must be in [0, 1)")

    component_value = sum(component.attributable_value for component in components)
    equity_value = (
        component_value
        + non_operating_assets
        - debt
        - minority_interest
        - other_claims
    )
    return SotPResult(
        component_value=component_value,
        non_operating_assets=non_operating_assets,
        debt=debt,
        minority_interest=minority_interest,
        other_claims=other_claims,
        equity_value=equity_value,
        value_per_share=equity_value / shares_outstanding,
        components=tuple(components),
    )
