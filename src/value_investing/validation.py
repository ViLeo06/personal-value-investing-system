"""Versioned validation-report aggregation and allocation gates."""
from __future__ import annotations

from dataclasses import asdict, dataclass
from enum import StrEnum
from typing import Iterable

from .hashing import sha256_hex
from .quality import AllocationEligibility


class ValidationSeverity(StrEnum):
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


class ValidationStatus(StrEnum):
    PASSED = "passed"
    PASSED_WITH_WARNINGS = "passed_with_warnings"
    FAILED = "failed"


@dataclass(frozen=True)
class ValidationRuleResult:
    rule_code: str
    severity: ValidationSeverity
    passed: bool
    message: str
    blocks_allocation: bool = False


@dataclass(frozen=True)
class ValidationReport:
    ruleset_version: str
    status: ValidationStatus
    allocation_eligibility: AllocationEligibility
    results: tuple[ValidationRuleResult, ...]
    report_hash: str


def build_validation_report(
    ruleset_version: str,
    results: Iterable[ValidationRuleResult],
    *,
    eligible_when_clean: bool = True,
) -> ValidationReport:
    if not ruleset_version:
        raise ValueError("ruleset version is required")
    rows = tuple(sorted(results, key=lambda row: row.rule_code))
    if not rows:
        raise ValueError("at least one validation result is required")
    if len({row.rule_code for row in rows}) != len(rows):
        raise ValueError("validation rule codes must be unique")
    hard_failures = [
        row
        for row in rows
        if not row.passed
        and row.severity in {ValidationSeverity.ERROR, ValidationSeverity.CRITICAL}
    ]
    warnings = [
        row
        for row in rows
        if not row.passed and row.severity == ValidationSeverity.WARNING
    ]
    blockers = [row for row in rows if not row.passed and row.blocks_allocation]

    if hard_failures:
        status = ValidationStatus.FAILED
    elif warnings:
        status = ValidationStatus.PASSED_WITH_WARNINGS
    else:
        status = ValidationStatus.PASSED

    if hard_failures:
        eligibility = AllocationEligibility.BLOCKED
    elif blockers or not eligible_when_clean:
        eligibility = AllocationEligibility.RESEARCH_ONLY
    else:
        eligibility = AllocationEligibility.ELIGIBLE

    payload = {
        "ruleset_version": ruleset_version,
        "status": status.value,
        "allocation_eligibility": eligibility.value,
        "results": [asdict(row) for row in rows],
    }
    return ValidationReport(
        ruleset_version=ruleset_version,
        status=status,
        allocation_eligibility=eligibility,
        results=rows,
        report_hash=sha256_hex(payload),
    )
