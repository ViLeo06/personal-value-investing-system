"""Versioned, date-effective transaction-cost calculations."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from math import isfinite
from typing import Iterable


@dataclass(frozen=True)
class CostComponent:
    policy_version: str
    market_code: str
    security_type: str
    side: str
    component_code: str
    valid_from: date
    valid_to: date | None
    rate: float
    minimum_amount: float = 0.0

    def __post_init__(self) -> None:
        if not self.policy_version:
            raise ValueError("policy_version is required")
        if not self.market_code:
            raise ValueError("market_code is required")
        if not self.security_type:
            raise ValueError("security_type is required")
        if self.side not in {"buy", "sell", "both"}:
            raise ValueError("side must be buy, sell, or both")
        if not self.component_code:
            raise ValueError("component_code is required")
        if self.valid_to is not None and self.valid_to < self.valid_from:
            raise ValueError("valid_to cannot precede valid_from")
        if not isfinite(self.rate) or self.rate < 0:
            raise ValueError("rate must be a finite non-negative number")
        if not isfinite(self.minimum_amount) or self.minimum_amount < 0:
            raise ValueError("minimum_amount must be a finite non-negative number")

    def applies_on(self, trade_date: date, side: str) -> bool:
        return (
            self.valid_from <= trade_date
            and (self.valid_to is None or trade_date <= self.valid_to)
            and self.side in {"both", side}
        )

    def charge(self, notional: float) -> float:
        return max(notional * self.rate, self.minimum_amount)


def calculate_transaction_cost(
    components: Iterable[CostComponent],
    *,
    policy_version: str,
    market_code: str,
    security_type: str,
    side: str,
    trade_date: date,
    notional: float,
) -> tuple[float, dict[str, float]]:
    """Return total cost and a component-level audit breakdown.

    Every component is selected independently by policy, market, security type,
    side and inclusive validity dates. Overlapping active rows for the same
    component code are rejected because silently double-charging a fee would
    make historical replay non-deterministic.
    """

    if side not in {"buy", "sell"}:
        raise ValueError("side must be buy or sell")
    if not isinstance(trade_date, date):
        raise TypeError("trade_date must be a date")
    if not isfinite(notional) or notional < 0:
        raise ValueError("notional must be a finite non-negative number")

    active = [
        component
        for component in components
        if component.policy_version == policy_version
        and component.market_code == market_code
        and component.security_type == security_type
        and component.applies_on(trade_date, side)
    ]
    if not active:
        raise ValueError(
            "no cost components for the requested policy, market, security, "
            "side, and trade date"
        )

    detail: dict[str, float] = {}
    for component in active:
        if component.component_code in detail:
            raise ValueError(
                f"overlapping active cost components: {component.component_code}"
            )
        detail[component.component_code] = component.charge(notional)
    return sum(detail.values()), detail
