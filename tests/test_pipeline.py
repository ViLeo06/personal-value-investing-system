from dataclasses import replace
from datetime import datetime, timezone

import pytest

from value_investing.pipeline import (
    PipelineControlError,
    build_run_manifest,
    evaluate_data_gate,
    freeze_phase_a,
    verify_phase_a_replay,
)


SNAPSHOT_HASH = "a" * 64


def test_data_gate_reports_missing_and_invalid_inputs() -> None:
    result = evaluate_data_gate(
        {"revenue": 100.0, "net_cash": None},
        ("revenue", "net_cash", "shares_outstanding"),
    )
    assert not result.passed
    assert result.missing == ("shares_outstanding",)
    assert result.null_or_nonfinite == ("net_cash",)


def test_manifest_hash_is_order_independent_for_parameters() -> None:
    first = build_run_manifest(
        issuer_code="TEST",
        security_code="TEST.SH",
        as_of_at=datetime(2021, 4, 1, tzinfo=timezone.utc),
        snapshot_hash=SNAPSHOT_HASH,
        snapshot_policy_version="v3",
        model_family="owner_earnings_dcf",
        model_version="1.0.0",
        scenario_set_version="base-v1",
        parameters={"wacc": 0.09, "growth": 0.03},
    )
    second = build_run_manifest(
        issuer_code="TEST",
        security_code="TEST.SH",
        as_of_at=datetime(2021, 4, 1, tzinfo=timezone.utc),
        snapshot_hash=SNAPSHOT_HASH,
        snapshot_policy_version="v3",
        model_family="owner_earnings_dcf",
        model_version="1.0.0",
        scenario_set_version="base-v1",
        parameters={"growth": 0.03, "wacc": 0.09},
    )
    assert first.parameter_hash == second.parameter_hash
    assert first.run_hash == second.run_hash


def test_incomplete_data_cannot_be_frozen_as_completed_phase_a() -> None:
    manifest = build_run_manifest(
        issuer_code="TEST",
        security_code="TEST.SH",
        as_of_at=datetime(2021, 4, 1, tzinfo=timezone.utc),
        snapshot_hash=SNAPSHOT_HASH,
        snapshot_policy_version="v3",
        model_family="owner_earnings_dcf",
        model_version="1.0.0",
        scenario_set_version="base-v1",
        parameters={},
    )
    gate = evaluate_data_gate({}, ("revenue",))
    with pytest.raises(PipelineControlError, match="cannot be frozen"):
        freeze_phase_a(
            manifest=manifest,
            assumptions={},
            data_quality=gate,
            frozen_at=datetime(2021, 4, 1, tzinfo=timezone.utc),
        )


def test_phase_a_replay_detects_tampering() -> None:
    manifest = build_run_manifest(
        issuer_code="TEST",
        security_code="TEST.SH",
        as_of_at=datetime(2021, 4, 1, tzinfo=timezone.utc),
        snapshot_hash=SNAPSHOT_HASH,
        snapshot_policy_version="v3",
        model_family="owner_earnings_dcf",
        model_version="1.0.0",
        scenario_set_version="base-v1",
        parameters={"growth": 0.05},
    )
    gate = evaluate_data_gate({"revenue": 100.0}, ("revenue",))
    frozen = freeze_phase_a(
        manifest=manifest,
        assumptions={"growth": 0.05},
        data_quality=gate,
        frozen_at=datetime(2021, 4, 1, tzinfo=timezone.utc),
    )
    assert verify_phase_a_replay(frozen)
    tampered = replace(frozen, assumptions={"growth": 0.50})
    assert not verify_phase_a_replay(tampered)
