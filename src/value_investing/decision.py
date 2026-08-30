"""Decision rules kept separate from valuation mathematics."""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite
from typing import Mapping


@dataclass(frozen=True)
class DecisionResult:
    signal: str
    rationale: tuple[str, ...]
    base_irr: float
    optimistic_irr: float
    hurdle: float
    data_quality: str


def classify_five_year_opportunity(
    scenario_irrs: Mapping[str, float],
    *,
    hurdle: float = 0.15,
    data_quality: str = "provisional",
) -> DecisionResult:
    required = {"pessimistic", "base", "optimistic"}
    missing = required.difference(scenario_irrs)
    if missing:
        raise ValueError(f"missing scenarios: {sorted(missing)}")
    if not all(isfinite(scenario_irrs[key]) for key in required):
        raise ValueError("scenario IRRs must be finite")
    if hurdle <= -1:
        raise ValueError("hurdle must be greater than -100%")

    base = scenario_irrs["base"]
    optimistic = scenario_irrs["optimistic"]
    reasons: list[str] = []
    if base >= hurdle:
        signal = "research_buy_candidate"
        reasons.append("base-case five-year IRR meets the investment hurdle")
    elif optimistic >= hurdle:
        signal = "watch_wait"
        reasons.append("only the optimistic scenario meets the investment hurdle")
    else:
        signal = "avoid_at_price"
        reasons.append("even the optimistic scenario is below the investment hurdle")
    if data_quality != "validated":
        reasons.append(
            f"data quality is {data_quality}; result is not eligible for automatic capital allocation"
        )
    return DecisionResult(signal, tuple(reasons), base, optimistic, hurdle, data_quality)
