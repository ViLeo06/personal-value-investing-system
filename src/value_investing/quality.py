"""Fail-closed data-quality gates for research and capital allocation."""
from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum, StrEnum
from typing import Iterable


class EvidenceQuality(IntEnum):
    MISSING = 0
    PROXY = 1
    DERIVED_ARCHIVE = 2
    RECONCILED = 3
    OFFICIAL = 4


class AllocationEligibility(StrEnum):
    BLOCKED = "blocked"
    RESEARCH_ONLY = "research_only"
    ELIGIBLE = "eligible"


@dataclass(frozen=True)
class QualityIssue:
    code: str
    severity: str
    description: str
    blocks_allocation: bool = True


@dataclass(frozen=True)
class QualityGateResult:
    eligibility: AllocationEligibility
    minimum_evidence_quality: EvidenceQuality
    blocking_codes: tuple[str, ...]
    issue_count: int


def evaluate_quality_gate(
    evidence_qualities: Iterable[EvidenceQuality],
    issues: Iterable[QualityIssue],
    *,
    minimum_for_allocation: EvidenceQuality = EvidenceQuality.RECONCILED,
) -> QualityGateResult:
    qualities = tuple(evidence_qualities)
    issue_rows = tuple(issues)
    minimum = min(qualities, default=EvidenceQuality.MISSING)
    blockers = tuple(sorted(issue.code for issue in issue_rows if issue.blocks_allocation))

    if minimum < EvidenceQuality.DERIVED_ARCHIVE:
        eligibility = AllocationEligibility.BLOCKED
    elif minimum < minimum_for_allocation or blockers:
        eligibility = AllocationEligibility.RESEARCH_ONLY
    else:
        eligibility = AllocationEligibility.ELIGIBLE

    return QualityGateResult(
        eligibility=eligibility,
        minimum_evidence_quality=minimum,
        blocking_codes=blockers,
        issue_count=len(issue_rows),
    )
