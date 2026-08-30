from value_investing.quality import AllocationEligibility
from value_investing.validation import (
    ValidationRuleResult,
    ValidationSeverity,
    ValidationStatus,
    build_validation_report,
)


def test_clean_report_is_eligible():
    report = build_validation_report(
        "rules-v1",
        [
            ValidationRuleResult(
                "PIT_NO_LEAKAGE", ValidationSeverity.CRITICAL, True, "No leakage"
            ),
            ValidationRuleResult(
                "SOURCE_OFFICIAL", ValidationSeverity.WARNING, True, "Official"
            ),
        ],
    )
    assert report.status == ValidationStatus.PASSED
    assert report.allocation_eligibility == AllocationEligibility.ELIGIBLE
    assert len(report.report_hash) == 64


def test_warning_can_block_allocation_without_failing_calculation():
    report = build_validation_report(
        "rules-v1",
        [
            ValidationRuleResult(
                "PIT_NO_LEAKAGE", ValidationSeverity.CRITICAL, True, "No leakage"
            ),
            ValidationRuleResult(
                "MARKET_DATA_OFFICIAL",
                ValidationSeverity.WARNING,
                False,
                "Provisional close",
                blocks_allocation=True,
            ),
        ],
    )
    assert report.status == ValidationStatus.PASSED_WITH_WARNINGS
    assert report.allocation_eligibility == AllocationEligibility.RESEARCH_ONLY


def test_error_fails_and_blocks():
    report = build_validation_report(
        "rules-v1",
        [
            ValidationRuleResult(
                "DETERMINISTIC_REPLAY",
                ValidationSeverity.ERROR,
                False,
                "Hash mismatch",
                blocks_allocation=True,
            )
        ],
    )
    assert report.status == ValidationStatus.FAILED
    assert report.allocation_eligibility == AllocationEligibility.BLOCKED
