"""Point-in-time eligibility helpers.

All historical research must apply the same cutoff semantics before any
normalization, valuation or backtest logic sees a record.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Iterable, Protocol, TypeVar


class HasAvailableAt(Protocol):
    available_at: datetime


T = TypeVar("T", bound=HasAvailableAt)


@dataclass(frozen=True)
class PitCutoff:
    decision_at: datetime
    policy_version: str = "pit_cutoff_v1"

    def eligible(self, available_at: datetime) -> bool:
        if available_at.tzinfo is None or self.decision_at.tzinfo is None:
            raise ValueError("PIT timestamps must be timezone-aware")
        return available_at <= self.decision_at


def eligible_records(records: Iterable[T], cutoff: PitCutoff) -> list[T]:
    """Return only records knowable at the decision timestamp."""
    return [record for record in records if cutoff.eligible(record.available_at)]


def assert_no_future_leakage(records: Iterable[T], cutoff: PitCutoff) -> None:
    """Fail fast if a downstream dataset contains future information."""
    leaked = [record for record in records if not cutoff.eligible(record.available_at)]
    if leaked:
        raise ValueError(f"PIT leakage detected: {len(leaked)} record(s) after cutoff")
