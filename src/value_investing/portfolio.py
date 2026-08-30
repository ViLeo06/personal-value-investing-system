"""Simple, auditable portfolio allocation for low-turnover value research."""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite
from typing import Iterable

from .quality import AllocationEligibility


@dataclass(frozen=True)
class PortfolioCandidate:
    security_code: str
    signal: str
    rank_value: float
    quality_eligibility: AllocationEligibility


@dataclass(frozen=True)
class AllocationPolicy:
    maximum_positions: int
    maximum_weight: float
    cash_buffer: float = 0.0
    eligible_signals: tuple[str, ...] = ("research_buy_candidate",)


@dataclass(frozen=True)
class AllocationResult:
    weights: tuple[tuple[str, float], ...]
    cash_weight: float
    excluded: tuple[tuple[str, str], ...]


def allocate_equal_weight(
    candidates: Iterable[PortfolioCandidate], policy: AllocationPolicy
) -> AllocationResult:
    if policy.maximum_positions < 1:
        raise ValueError("maximum positions must be positive")
    if not 0 < policy.maximum_weight <= 1:
        raise ValueError("maximum weight must be in (0, 1]")
    if not 0 <= policy.cash_buffer <= 1:
        raise ValueError("cash buffer must be in [0, 1]")

    candidate_rows = tuple(candidates)
    codes = [candidate.security_code for candidate in candidate_rows]
    if len(codes) != len(set(codes)):
        raise ValueError("security codes must be unique")
    if any(not isfinite(candidate.rank_value) for candidate in candidate_rows):
        raise ValueError("candidate ranks must be finite")

    eligible: list[PortfolioCandidate] = []
    excluded: list[tuple[str, str]] = []
    for candidate in candidate_rows:
        if candidate.quality_eligibility != AllocationEligibility.ELIGIBLE:
            excluded.append((candidate.security_code, "quality_gate"))
        elif candidate.signal not in policy.eligible_signals:
            excluded.append((candidate.security_code, "signal_gate"))
        else:
            eligible.append(candidate)

    selected = sorted(
        eligible, key=lambda candidate: (-candidate.rank_value, candidate.security_code)
    )[: policy.maximum_positions]
    selected_codes = {candidate.security_code for candidate in selected}
    for candidate in eligible:
        if candidate.security_code not in selected_codes:
            excluded.append((candidate.security_code, "position_limit"))

    investable = 1.0 - policy.cash_buffer
    if not selected or investable <= 0:
        return AllocationResult((), 1.0, tuple(sorted(excluded)))

    equal_weight = min(investable / len(selected), policy.maximum_weight)
    weights = tuple(
        sorted((candidate.security_code, equal_weight) for candidate in selected)
    )
    invested = sum(weight for _, weight in weights)
    return AllocationResult(
        weights=weights,
        cash_weight=1.0 - invested,
        excluded=tuple(sorted(excluded)),
    )
