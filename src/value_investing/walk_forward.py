"""PIT-safe walk-forward orchestration independent of valuation family."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from typing import Callable, Generic, Iterable, Mapping, Protocol, Sequence, TypeVar

from .hashing import sha256_hex
from .pit import PitCutoff, assert_no_future_leakage


class AvailableRecord(Protocol):
    available_at: datetime


T = TypeVar("T", bound=AvailableRecord)
R = TypeVar("R")


@dataclass(frozen=True)
class HistoricalMembership:
    security_code: str
    valid_from: date
    valid_to: date | None = None

    def is_member(self, decision_date: date) -> bool:
        return self.valid_from <= decision_date and (
            self.valid_to is None or decision_date <= self.valid_to
        )


@dataclass(frozen=True)
class DecisionPoint:
    decision_at: datetime
    cohort_code: str

    def __post_init__(self) -> None:
        if self.decision_at.tzinfo is None:
            raise ValueError("decision timestamp must be timezone-aware")
        if not self.cohort_code:
            raise ValueError("cohort code is required")


@dataclass(frozen=True)
class FrozenResearchInput(Generic[T]):
    decision: DecisionPoint
    security_code: str
    records: tuple[T, ...]
    snapshot_hash: str


@dataclass(frozen=True)
class WalkForwardResult(Generic[R]):
    decision: DecisionPoint
    security_code: str
    snapshot_hash: str
    model_version: str
    result: R
    run_hash: str


class RecordLoader(Protocol[T]):
    def __call__(self, security_code: str, cutoff: PitCutoff) -> Sequence[T]: ...


class ModelEvaluator(Protocol[T, R]):
    def __call__(
        self,
        security_code: str,
        decision: DecisionPoint,
        records: Sequence[T],
    ) -> R: ...


def eligible_universe(
    memberships: Iterable[HistoricalMembership], decision_date: date
) -> tuple[str, ...]:
    """Return historical constituents without consulting current membership."""
    return tuple(
        sorted(
            membership.security_code
            for membership in memberships
            if membership.is_member(decision_date)
        )
    )


def freeze_records(
    decision: DecisionPoint,
    security_code: str,
    records: Sequence[T],
    *,
    record_fingerprint: Callable[[T], str],
) -> FrozenResearchInput[T]:
    cutoff = PitCutoff(decision.decision_at)
    assert_no_future_leakage(records, cutoff)
    fingerprints = sorted(record_fingerprint(record) for record in records)
    if len(fingerprints) != len(set(fingerprints)):
        raise ValueError("duplicate record fingerprints in frozen input")
    manifest = {
        "cohort_code": decision.cohort_code,
        "decision_at": decision.decision_at.isoformat(),
        "security_code": security_code,
        "record_fingerprints": fingerprints,
        "record_count": len(fingerprints),
        "cutoff_policy": cutoff.policy_version,
    }
    return FrozenResearchInput(
        decision=decision,
        security_code=security_code,
        records=tuple(records),
        snapshot_hash=sha256_hex(manifest),
    )


def run_walk_forward(
    *,
    decision_points: Sequence[DecisionPoint],
    memberships: Sequence[HistoricalMembership],
    load_records: RecordLoader[T],
    evaluate: ModelEvaluator[T, R],
    record_fingerprint: Callable[[T], str],
    model_version: str,
) -> tuple[WalkForwardResult[R], ...]:
    """Evaluate each historical constituent at each fixed decision timestamp."""
    if not model_version:
        raise ValueError("model version is required")
    if list(decision_points) != sorted(
        decision_points, key=lambda point: point.decision_at
    ):
        raise ValueError("decision points must be chronological")

    results: list[WalkForwardResult[R]] = []
    for decision in decision_points:
        securities = eligible_universe(memberships, decision.decision_at.date())
        cutoff = PitCutoff(decision.decision_at)
        for security_code in securities:
            records = tuple(load_records(security_code, cutoff))
            frozen = freeze_records(
                decision,
                security_code,
                records,
                record_fingerprint=record_fingerprint,
            )
            result = evaluate(security_code, decision, frozen.records)
            run_hash = sha256_hex(
                {
                    "snapshot_hash": frozen.snapshot_hash,
                    "model_version": model_version,
                    "security_code": security_code,
                    "decision_at": decision.decision_at.isoformat(),
                }
            )
            results.append(
                WalkForwardResult(
                    decision=decision,
                    security_code=security_code,
                    snapshot_hash=frozen.snapshot_hash,
                    model_version=model_version,
                    result=result,
                    run_hash=run_hash,
                )
            )
    return tuple(results)
