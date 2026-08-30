from datetime import datetime, timedelta, timezone

from value_investing.contracts import ContractCheck, Readiness
from value_investing.data_quality import (
    RunQualityContext,
    Severity,
    evaluate_run_quality,
    results_as_rows,
)


UTC = timezone.utc
NOW = datetime(2026, 8, 30, 10, 0, tzinfo=UTC)


def contract(readiness: Readiness = Readiness.VALIDATED) -> ContractCheck:
    return ContractCheck(
        model_family="owner_earnings_dcf",
        readiness=readiness,
        missing_metrics=(),
        future_metrics=(),
        unit_errors=(),
        unhashed_metrics=(),
        provisional_metrics=(),
    )


def complete_context(**overrides):
    values = dict(
        cutoff=NOW,
        contract_check=contract(),
        all_required_evidence_hashed=True,
        evidence_durable=True,
        input_hash_present=True,
        output_hash_present=True,
        parameter_set_frozen=True,
        calendar_version_frozen=True,
        market_price_authoritative=True,
        corporate_actions_complete=True,
        exact_daily_total_return=True,
        phase_a_frozen_at=NOW,
        phase_b_revealed_at=NOW + timedelta(days=1),
        release_manifest_complete=True,
        future_financial_fact_count=0,
        future_normalized_fact_count=0,
    )
    values.update(overrides)
    return RunQualityContext(**values)


def test_complete_run_is_validated():
    assessment = evaluate_run_quality(complete_context())
    assert assessment.readiness is Readiness.VALIDATED
    assert not assessment.failed_rules
    assert not assessment.blocking_rules


def test_warning_only_gap_is_provisional():
    assessment = evaluate_run_quality(
        complete_context(
            evidence_durable=False,
            market_price_authoritative=False,
        )
    )
    assert assessment.readiness is Readiness.PROVISIONAL
    assert {item.rule_code for item in assessment.failed_rules} == {
        "EVD002",
        "MKT001",
    }
    assert all(item.severity is Severity.WARNING for item in assessment.failed_rules)


def test_future_fact_or_missing_hash_blocks():
    assessment = evaluate_run_quality(
        complete_context(
            all_required_evidence_hashed=False,
            future_financial_fact_count=1,
        )
    )
    assert assessment.readiness is Readiness.BLOCKED
    assert {item.rule_code for item in assessment.blocking_rules} >= {
        "PIT002",
        "EVD001",
    }


def test_phase_b_before_phase_a_blocks():
    assessment = evaluate_run_quality(
        complete_context(
            phase_a_frozen_at=NOW,
            phase_b_revealed_at=NOW - timedelta(seconds=1),
        )
    )
    assert assessment.readiness is Readiness.BLOCKED
    assert "PHS001" in {item.rule_code for item in assessment.blocking_rules}


def test_provisional_contract_keeps_otherwise_complete_run_provisional():
    assessment = evaluate_run_quality(
        complete_context(contract_check=contract(Readiness.PROVISIONAL))
    )
    assert assessment.readiness is Readiness.PROVISIONAL
    assert not assessment.failed_rules


def test_rows_are_stable_and_include_descriptions():
    assessment = evaluate_run_quality(complete_context())
    rows = results_as_rows(
        "valuation",
        "00000000-0000-0000-0000-000000000001",
        "00000000-0000-0000-0000-000000000002",
        assessment,
    )
    assert len(rows) == 15
    assert rows[0]["rule_code"] == "PIT001"
    assert rows[0]["details"]["description"]
