"""五年情景分析。"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .finance import irr, target_entry_price


@dataclass(frozen=True)
class Scenario:
    name: str
    probability: float
    annual_distributions: tuple[float, ...]
    exit_value: float

    def validate(self) -> None:
        if not self.name.strip():
            raise ValueError("情景名称不能为空")
        if not 0.0 <= self.probability <= 1.0:
            raise ValueError("情景概率必须在 0 到 1 之间")
        if not self.annual_distributions:
            raise ValueError("情景必须包含至少一年的分配")
        if self.exit_value < 0 or any(value < 0 for value in self.annual_distributions):
            raise ValueError("分配和退出价值不能为负")


def analyze_scenarios(
    entry_price: float, scenarios: list[Scenario], target_rate: float = 0.15
) -> dict[str, Any]:
    if entry_price <= 0:
        raise ValueError("进入价格必须为正数")
    if not scenarios:
        raise ValueError("至少需要一个情景")
    for scenario in scenarios:
        scenario.validate()

    probability_sum = sum(item.probability for item in scenarios)
    if abs(probability_sum - 1.0) > 1e-9:
        raise ValueError("情景概率合计必须等于 1")

    rows: list[dict[str, Any]] = []
    weighted_irr = 0.0
    weighted_target_price = 0.0
    for item in scenarios:
        cash_flows = [-entry_price, *item.annual_distributions]
        cash_flows[-1] += item.exit_value
        scenario_irr = irr(cash_flows)
        scenario_target = target_entry_price(
            item.annual_distributions, item.exit_value, target_rate
        )
        weighted_irr += item.probability * scenario_irr
        weighted_target_price += item.probability * scenario_target
        rows.append(
            {
                "name": item.name,
                "probability": item.probability,
                "irr": scenario_irr,
                "target_entry_price": scenario_target,
            }
        )

    return {
        "entry_price": entry_price,
        "target_rate": target_rate,
        "probability_weighted_irr": weighted_irr,
        "probability_weighted_target_entry_price": weighted_target_price,
        "scenarios": rows,
    }

