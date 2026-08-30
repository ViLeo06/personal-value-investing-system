import json
from datetime import datetime, timezone

import pytest

from value_investing.cli import (
    canonical_json,
    main,
    manifest_hash,
    validate_contract_payload,
    value_payload,
)


def test_manifest_hash_is_order_independent():
    left = {"b": 2, "a": {"y": 2, "x": 1}}
    right = {"a": {"x": 1, "y": 2}, "b": 2}
    assert canonical_json(left) == canonical_json(right)
    assert manifest_hash(left) == manifest_hash(right)


def test_validate_contract_payload_reports_validated():
    cutoff = "2021-08-30T07:00:00+00:00"
    observations = []
    units = {
        "revenue": "CNY",
        "net_income_parent": "CNY",
        "operating_cash_flow": "CNY",
        "maintenance_capex": "CNY",
        "shares_outstanding": "shares",
    }
    for metric_code, unit in units.items():
        observations.append(
            {
                "metric_code": metric_code,
                "value": 1.0,
                "unit": unit,
                "available_at": "2021-08-29T07:00:00+00:00",
                "evidence_tier": "official_binary",
                "record_hash": f"sha256:{metric_code}",
            }
        )
    payload = {
        "model_family": "owner_earnings_dcf",
        "cutoff": cutoff,
        "observations": observations,
    }
    result = validate_contract_payload(payload)
    assert result["readiness"] == "validated"
    assert result["is_usable"] is True
    assert len(result["input_hash"]) == 64


def test_value_payload_is_deterministic():
    payload = {
        "model_family": "value_driver_fcff",
        "assumptions": {
            "starting_nopat": 100.0,
            "first_five_year_growth": 0.12,
            "starting_ronic": 0.22,
            "terminal_ronic": 0.10,
            "discount_rate": 0.10,
            "perpetual_growth": 0.025,
            "net_debt": 20.0,
            "shares_outstanding": 10.0,
        },
    }
    first = value_payload(payload)
    second = value_payload(payload)
    assert first == second
    assert len(first["input_hash"]) == 64
    assert len(first["output_hash"]) == 64


def test_cli_hash_manifest(tmp_path, capsys):
    path = tmp_path / "input.json"
    path.write_text(json.dumps({"b": 2, "a": 1}), encoding="utf-8")
    assert main(["hash-manifest", str(path)]) == 0
    output = json.loads(capsys.readouterr().out)
    assert output["input_hash"] == manifest_hash({"a": 1, "b": 2})


def test_cli_rejects_naive_cutoff(tmp_path):
    path = tmp_path / "input.json"
    path.write_text(
        json.dumps(
            {
                "model_family": "owner_earnings_dcf",
                "cutoff": "2021-08-30T07:00:00",
                "observations": [],
            }
        ),
        encoding="utf-8",
    )
    with pytest.raises(ValueError):
        main(["validate-contract", str(path)])
