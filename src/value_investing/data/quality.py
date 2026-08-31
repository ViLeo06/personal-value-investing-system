from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum
from typing import Iterable


class EvidenceGrade(IntEnum):
    UNUSABLE = 0
    SINGLE_DERIVED = 1
    CROSS_VALIDATED = 2
    OFFICIAL_PRIMARY = 3


@dataclass(frozen=True, slots=True)
class EvidenceAssertion:
    assertion_code: str
    grade: EvidenceGrade
    source_codes: tuple[str, ...]
    content_hashes: tuple[str, ...] = ()
    unresolved_conflict: bool = False


@dataclass(frozen=True, slots=True)
class QualityPolicy:
    required_assertions: tuple[str, ...]
    minimum_grade: EvidenceGrade = EvidenceGrade.CROSS_VALIDATED
    require_content_hash: bool = True


@dataclass(frozen=True, slots=True)
class QualityDecision:
    passed: bool
    missing: tuple[str, ...]
    below_grade: tuple[str, ...]
    missing_hash: tuple[str, ...]
    conflicts: tuple[str, ...]


def evaluate_evidence(
    assertions: Iterable[EvidenceAssertion], policy: QualityPolicy
) -> QualityDecision:
    indexed = {assertion.assertion_code: assertion for assertion in assertions}
    missing: list[str] = []
    below_grade: list[str] = []
    missing_hash: list[str] = []
    conflicts: list[str] = []
    for code in policy.required_assertions:
        assertion = indexed.get(code)
        if assertion is None:
            missing.append(code)
            continue
        if assertion.grade < policy.minimum_grade:
            below_grade.append(code)
        if policy.require_content_hash and not assertion.content_hashes:
            missing_hash.append(code)
        if assertion.unresolved_conflict:
            conflicts.append(code)
    return QualityDecision(
        passed=not (missing or below_grade or missing_hash or conflicts),
        missing=tuple(sorted(missing)),
        below_grade=tuple(sorted(below_grade)),
        missing_hash=tuple(sorted(missing_hash)),
        conflicts=tuple(sorted(conflicts)),
    )
