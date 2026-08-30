from datetime import datetime, timedelta, timezone

import pytest

from value_investing.contracts import (
    EvidenceTier,
    MetricObservation,
    Readiness,
    validate_model_inputs,
)


UTC = timezone.utc
CUTOFF = datetime(2021, 8, 30, 7, 0, tzinfo=UTC)


def observation(
    metric_code: str,
    *,
    unit: str,
    evidence_tier: EvidenceTier = EvidenceTier.OFFICIAL_BINARY,
    available_at: datetime = CUTOFF - timedelta(days=1),
    record_hash: str | None = "sha256:test",
) -> MetricObservation:
    return MetricObservation(
        metric_code=metric_code,
        value=1.0,
        unit=unit,
        available_at=available_at,
        evidence_tier=evidence_tier,
        record_hash=record_hash,
    )


def test_validated_owner_earnings_contract():
    rows = [
        observation("revenue", unit="CNY"),
        observation("net_income_parent", unit="CNY"),
        observation("operating_cash_flow", unit="CNY"),
        observation("maintenance_capex", unit="CNY"),
        observation("shares_outstanding", unit="shares"),
    ]
    result = validate_model_inputs(
        "owner_earnings_dcf",
        rows,
        cutoff=CUTOFF,
    )
    assert result.readiness is Readiness.VALIDATED
    assert result.is_usable
    assert not result.missing_metrics


def test_missing_required_metric_blocks_run():
    rows = [
        observation("revenue", unit="CNY"),
        observation("net_income_parent", unit="CNY"),
        observation("operating_cash_flow", unit="CNY"),
        observation("shares_outstanding", unit="shares"),
    ]
    result = validate_model_inputs(
        "owner_earnings_dcf",
        rows,
        cutoff=CUTOFF,
    )
    assert result.readiness is Readiness.BLOCKED
    assert result.missing_metrics == ("maintenance_capex",)


def test_future_revision_is_not_selected_over_eligible_fact():
    rows = [
        observation("book_value_per_share", unit="CNY/share"),
        observation("roe", unit="ratio"),
        observation("payout_ratio", unit="ratio"),
        observation("cost_of_equity", unit="ratio"),
        observation(
            "roe",
            unit="ratio",
            available_at=CUTOFF + timedelta(days=30),
            record_hash="sha256:future",
        ),
    ]
    result = validate_model_inputs("residual_income", rows, cutoff=CUTOFF)
    assert result.readiness is Readiness.VALIDATED
    assert result.future_metrics == ("roe",)


def test_proxy_or_unhashed_evidence_is_provisional():
    rows = [
        observation("nopat", unit="CNY"),
        observation("ronic", unit="ratio"),
        observation(
            "net_debt",
            unit="CNY",
            evidence_tier=EvidenceTier.AGGREGATOR,
        ),
        observation(
            "shares_outstanding",
            unit="shares",
            record_hash=None,
        ),
    ]
    result = validate_model_inputs(
        "value_driver_fcff",
        rows,
        cutoff=CUTOFF,
    )
    assert result.readiness is Readiness.PROVISIONAL
    assert result.provisional_metrics == ("net_debt",)
    assert result.unhashed_metrics == ("shares_outstanding",)


def test_unit_mismatch_blocks_run():
    rows = [
        observation("book_value_per_share", unit="CNY"),
        observation("roe", unit="ratio"),
        observation("payout_ratio", unit="ratio"),
        observation("cost_of_equity", unit="ratio"),
    ]
    result = validate_model_inputs("residual_income", rows, cutoff=CUTOFF)
    assert result.readiness is Readiness.BLOCKED
    assert result.unit_errors == ("book_value_per_share",)


def test_naive_cutoff_is_rejected():
    with pytest.raises(ValueError):
        validate_model_inputs(
            "owner_earnings_dcf",
            [],
            cutoff=datetime(2021, 8, 30),
        )
