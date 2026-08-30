"""Deterministic run-quality evaluation.

The evaluator mirrors the frozen Gate-0 database rule set but stays independent
of PostgreSQL so fixtures and preview runs can fail before any database write.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from typing import Iterable

from .contracts import ContractCheck, Readiness


class Severity(str, Enum):
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


@dataclass(frozen=True)
class RuleResult:
    rule_code: str
    severity: Severity
    passed: bool
    description: str
    details: dict[str, object]


@dataclass(frozen=True)
class RunQualityContext:
    cutoff: datetime
    contract_check: ContractCheck
    all_required_evidence_hashed: bool
    evidence_durable: bool
    input_hash_present: bool
    output_hash_present: bool
    parameter_set_frozen: bool
    calendar_version_frozen: bool
    market_price_authoritative: bool
    corporate_actions_complete: bool
    exact_daily_total_return: bool
    phase_a_frozen_at: datetime | None
    phase_b_revealed_at: datetime | None
    release_manifest_complete: bool
    future_financial_fact_count: int = 0
    future_normalized_fact_count: int = 0


@dataclass(frozen=True)
class RunQualityAssessment:
    readiness: Readiness
    results: tuple[RuleResult, ...]

    @property
    def failed_rules(self) -> tuple[RuleResult, ...]:
        return tuple(result for result in self.results if not result.passed)

    @property
    def blocking_rules(self) -> tuple[RuleResult, ...]:
        return tuple(
            result
            for result in self.failed_rules
            if result.severity in {Severity.ERROR, Severity.CRITICAL}
        )


def _result(
    code: str,
    severity: Severity,
    passed: bool,
    description: str,
    **details: object,
) -> RuleResult:
    return RuleResult(
        rule_code=code,
        severity=severity,
        passed=passed,
        description=description,
        details=details,
    )


def evaluate_run_quality(context: RunQualityContext) -> RunQualityAssessment:
    if context.future_financial_fact_count < 0:
        raise ValueError("future_financial_fact_count cannot be negative")
    if context.future_normalized_fact_count < 0:
        raise ValueError("future_normalized_fact_count cannot be negative")

    cutoff_aware = context.cutoff.tzinfo is not None
    phase_order_valid = (
        context.phase_a_frozen_at is not None
        and context.phase_b_revealed_at is not None
        and context.phase_a_frozen_at.tzinfo is not None
        and context.phase_b_revealed_at.tzinfo is not None
        and context.phase_a_frozen_at <= context.phase_b_revealed_at
    )
    contract_metrics_present = not context.contract_check.missing_metrics
    contract_units_valid = not context.contract_check.unit_errors

    results = (
        _result(
            "PIT001",
            Severity.CRITICAL,
            cutoff_aware,
            "Decision cutoff is timezone-aware.",
        ),
        _result(
            "PIT002",
            Severity.CRITICAL,
            context.future_financial_fact_count == 0,
            "No future financial fact is referenced.",
            count=context.future_financial_fact_count,
        ),
        _result(
            "PIT003",
            Severity.CRITICAL,
            context.future_normalized_fact_count == 0,
            "No future normalized fact is referenced.",
            count=context.future_normalized_fact_count,
        ),
        _result(
            "EVD001",
            Severity.CRITICAL,
            context.all_required_evidence_hashed,
            "All required evidence has a content hash.",
        ),
        _result(
            "EVD002",
            Severity.WARNING,
            context.evidence_durable,
            "Required evidence is retained in durable private storage.",
        ),
        _result(
            "MOD001",
            Severity.ERROR,
            contract_metrics_present,
            "All required model-family metrics are present.",
            missing=list(context.contract_check.missing_metrics),
        ),
        _result(
            "MOD002",
            Severity.ERROR,
            contract_units_valid,
            "Canonical metric units satisfy the model contract.",
            unit_errors=list(context.contract_check.unit_errors),
        ),
        _result(
            "MOD003",
            Severity.CRITICAL,
            context.input_hash_present and context.output_hash_present,
            "Valuation input and output hashes are present.",
        ),
        _result(
            "PAR001",
            Severity.CRITICAL,
            context.parameter_set_frozen,
            "Formal run references a frozen parameter set.",
        ),
        _result(
            "CAL001",
            Severity.ERROR,
            context.calendar_version_frozen,
            "Execution uses a frozen exchange-calendar version.",
        ),
        _result(
            "MKT001",
            Severity.WARNING,
            context.market_price_authoritative,
            "Decision price is authoritative and unadjusted.",
        ),
        _result(
            "ACT001",
            Severity.WARNING,
            context.corporate_actions_complete,
            "Corporate actions are complete for the outcome window.",
        ),
        _result(
            "RET001",
            Severity.WARNING,
            context.exact_daily_total_return,
            "Outcome uses exact daily total return.",
        ),
        _result(
            "PHS001",
            Severity.CRITICAL,
            phase_order_valid,
            "Phase A was frozen before Phase B reveal.",
        ),
        _result(
            "REL001",
            Severity.CRITICAL,
            context.release_manifest_complete,
            "Formal release manifest is complete.",
        ),
    )

    failed = tuple(result for result in results if not result.passed)
    if any(
        result.severity in {Severity.ERROR, Severity.CRITICAL}
        for result in failed
    ):
        readiness = Readiness.BLOCKED
    elif failed or context.contract_check.readiness is Readiness.PROVISIONAL:
        readiness = Readiness.PROVISIONAL
    else:
        readiness = Readiness.VALIDATED
    return RunQualityAssessment(readiness=readiness, results=results)


def results_as_rows(
    run_type: str,
    run_id: str,
    quality_rule_set_id: str,
    assessment: RunQualityAssessment,
) -> tuple[dict[str, object], ...]:
    """Convert an assessment to deterministic database-ingestion rows."""
    return tuple(
        {
            "run_type": run_type,
            "run_id": run_id,
            "quality_rule_set_id": quality_rule_set_id,
            "rule_code": result.rule_code,
            "severity": result.severity.value,
            "passed": result.passed,
            "details": {
                "description": result.description,
                **result.details,
            },
        }
        for result in assessment.results
    )
