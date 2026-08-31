from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from typing import Sequence

from value_investing.valuation.core import bounded_bisection


class DecisionStatus(StrEnum):
    INSUFFICIENT_DATA = "insufficient_data"
    REJECTED = "rejected"
    BUY_CANDIDATE = "buy_candidate"
    WATCH = "watch"
    OVERVALUED = "overvalued"


@dataclass(frozen=True, slots=True)
class DecisionInput:
    reference_price: float
    base_intrinsic_value: float
    expected_exit_price: float
    expected_dividends: tuple[float, ...]
    hurdle_rate: float = 0.15
    minimum_margin_of_safety: float = 0.20
    data_quality_pass: bool = True
    hard_falsification: bool = False


@dataclass(frozen=True, slots=True)
class DecisionOutcome:
    status: DecisionStatus
    expected_irr: float | None
    hurdle_entry_price: float | None
    margin_of_safety: float | None
    reasons: tuple[str, ...]


def expected_irr(
    purchase_price: float,
    dividends: Sequence[float],
    exit_price: float,
) -> float:
    if purchase_price <= 0:
        raise ValueError("purchase_price must be positive")
    if exit_price < 0:
        raise ValueError("exit_price cannot be negative")
    horizon = len(dividends)
    if horizon < 1:
        raise ValueError("At least one holding-period cash flow is required")

    def npv(rate: float) -> float:
        return -purchase_price + sum(
            dividend / ((1.0 + rate) ** year)
            for year, dividend in enumerate(dividends, 1)
        ) + exit_price / ((1.0 + rate) ** horizon)

    return bounded_bisection(npv, -0.999, 10.0)


def hurdle_entry_price(
    dividends: Sequence[float], exit_price: float, hurdle_rate: float
) -> float:
    if hurdle_rate <= -1:
        raise ValueError("hurdle_rate must exceed -100%")
    horizon = len(dividends)
    return sum(
        dividend / ((1.0 + hurdle_rate) ** year)
        for year, dividend in enumerate(dividends, 1)
    ) + exit_price / ((1.0 + hurdle_rate) ** horizon)


def decide(inputs: DecisionInput) -> DecisionOutcome:
    if not inputs.data_quality_pass:
        return DecisionOutcome(
            status=DecisionStatus.INSUFFICIENT_DATA,
            expected_irr=None,
            hurdle_entry_price=None,
            margin_of_safety=None,
            reasons=("required PIT inputs or lineage are incomplete",),
        )
    if inputs.hard_falsification:
        return DecisionOutcome(
            status=DecisionStatus.REJECTED,
            expected_irr=None,
            hurdle_entry_price=None,
            margin_of_safety=None,
            reasons=("a hard falsification condition is active",),
        )
    if inputs.reference_price <= 0 or inputs.base_intrinsic_value <= 0:
        raise ValueError("reference price and intrinsic value must be positive")

    irr = expected_irr(
        inputs.reference_price,
        inputs.expected_dividends,
        inputs.expected_exit_price,
    )
    entry = hurdle_entry_price(
        inputs.expected_dividends,
        inputs.expected_exit_price,
        inputs.hurdle_rate,
    )
    margin = (inputs.base_intrinsic_value - inputs.reference_price) / inputs.base_intrinsic_value

    reasons: list[str] = []
    if irr >= inputs.hurdle_rate:
        reasons.append("expected IRR meets the investor hurdle")
    else:
        reasons.append("expected IRR is below the investor hurdle")
    if margin >= inputs.minimum_margin_of_safety:
        reasons.append("margin of safety meets the configured minimum")
    else:
        reasons.append("margin of safety is below the configured minimum")

    if irr >= inputs.hurdle_rate and margin >= inputs.minimum_margin_of_safety:
        status = DecisionStatus.BUY_CANDIDATE
    elif irr >= inputs.hurdle_rate or margin > 0:
        status = DecisionStatus.WATCH
    else:
        status = DecisionStatus.OVERVALUED
    return DecisionOutcome(
        status=status,
        expected_irr=irr,
        hurdle_entry_price=entry,
        margin_of_safety=margin,
        reasons=tuple(reasons),
    )
