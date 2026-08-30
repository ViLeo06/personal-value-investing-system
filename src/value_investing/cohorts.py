"""Cohort accounting for overlapping long-horizon decisions."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from typing import Iterable


@dataclass(frozen=True)
class CohortObservation:
    issuer_code: str
    security_code: str
    decision_date: date
    maturity_date: date
    model_family: str
    annualized_return: float | None = None

    @property
    def interval(self) -> tuple[date, date]:
        return self.decision_date, self.maturity_date


@dataclass(frozen=True)
class CohortSummary:
    total_observations: int
    mature_observations: int
    pending_observations: int
    unique_issuers: int
    unique_decision_dates: int
    non_overlapping_observations: tuple[CohortObservation, ...]


def is_mature(observation: CohortObservation, as_of: date) -> bool:
    return observation.maturity_date <= as_of


def intervals_overlap(left: CohortObservation, right: CohortObservation) -> bool:
    return max(left.decision_date, right.decision_date) < min(
        left.maturity_date, right.maturity_date
    )


def select_non_overlapping(
    observations: Iterable[CohortObservation],
) -> tuple[CohortObservation, ...]:
    """Greedy earliest-maturity interval selection within each security.

    The rule is deterministic and maximizes the count of non-overlapping
    intervals for the usual interval-scheduling objective.
    """
    rows = tuple(observations)
    selected: list[CohortObservation] = []
    for security_code in sorted({row.security_code for row in rows}):
        security_rows = sorted(
            (row for row in rows if row.security_code == security_code),
            key=lambda row: (row.maturity_date, row.decision_date),
        )
        last_maturity: date | None = None
        for row in security_rows:
            if last_maturity is None or row.decision_date >= last_maturity:
                selected.append(row)
                last_maturity = row.maturity_date
    return tuple(sorted(selected, key=lambda row: (row.decision_date, row.security_code)))


def summarize_cohorts(
    observations: Iterable[CohortObservation], as_of: date
) -> CohortSummary:
    rows = tuple(observations)
    mature = tuple(row for row in rows if is_mature(row, as_of))
    return CohortSummary(
        total_observations=len(rows),
        mature_observations=len(mature),
        pending_observations=len(rows) - len(mature),
        unique_issuers=len({row.issuer_code for row in rows}),
        unique_decision_dates=len({row.decision_date for row in rows}),
        non_overlapping_observations=select_non_overlapping(mature),
    )
