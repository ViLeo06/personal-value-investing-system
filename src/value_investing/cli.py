"""Deterministic offline command-line entry points.

The CLI never fetches network data. Inputs must already be frozen and hashed.
Database persistence belongs to a separate orchestration adapter so previewing a
valuation cannot mutate research history.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Any, Mapping, Sequence

from .contracts import EvidenceTier, MetricObservation, validate_model_inputs
from .fcff import FcffAssumptions, value_fcff
from .residual_income import ResidualIncomeAssumptions, value_residual_income
from .value_driver_fcff import ValueDriverAssumptions, value_value_driver


def canonical_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    )


def manifest_hash(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def load_json(path: str | Path) -> Any:
    with Path(path).open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _parse_timestamp(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError(f"timestamp must be timezone-aware: {value}")
    return parsed


def validate_contract_payload(payload: Mapping[str, Any]) -> Mapping[str, Any]:
    observations = [
        MetricObservation(
            metric_code=item["metric_code"],
            value=item["value"],
            unit=item.get("unit"),
            available_at=_parse_timestamp(item["available_at"]),
            evidence_tier=EvidenceTier(item["evidence_tier"]),
            record_hash=item.get("record_hash"),
        )
        for item in payload["observations"]
    ]
    result = validate_model_inputs(
        payload["model_family"],
        observations,
        cutoff=_parse_timestamp(payload["cutoff"]),
    )
    return {
        "model_family": result.model_family,
        "readiness": result.readiness.value,
        "is_usable": result.is_usable,
        "missing_metrics": list(result.missing_metrics),
        "future_metrics": list(result.future_metrics),
        "unit_errors": list(result.unit_errors),
        "unhashed_metrics": list(result.unhashed_metrics),
        "provisional_metrics": list(result.provisional_metrics),
        "input_hash": manifest_hash(payload),
    }


def value_payload(payload: Mapping[str, Any]) -> Mapping[str, Any]:
    family = payload["model_family"]
    assumptions_payload = payload["assumptions"]
    if family == "fcff_sotp":
        assumptions = FcffAssumptions(**assumptions_payload)
        result = value_fcff(assumptions)
    elif family == "value_driver_fcff":
        assumptions = ValueDriverAssumptions(**assumptions_payload)
        result = value_value_driver(assumptions)
    elif family == "residual_income":
        assumptions = ResidualIncomeAssumptions(**assumptions_payload)
        result = value_residual_income(assumptions)
    else:
        raise ValueError(
            "value command currently supports fcff_sotp, value_driver_fcff "
            "and residual_income; use the native consumer runner for "
            "owner_earnings_dcf"
        )
    result_payload = asdict(result)
    return {
        "model_family": family,
        "input_hash": manifest_hash(payload),
        "result": result_payload,
        "output_hash": manifest_hash(result_payload),
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="python -m value_investing")
    subparsers = parser.add_subparsers(dest="command", required=True)

    hash_parser = subparsers.add_parser(
        "hash-manifest",
        help="print the SHA-256 hash of canonical JSON",
    )
    hash_parser.add_argument("input", type=Path)

    contract_parser = subparsers.add_parser(
        "validate-contract",
        help="validate PIT model inputs without writing any data",
    )
    contract_parser.add_argument("input", type=Path)

    value_parser = subparsers.add_parser(
        "value",
        help="run a deterministic valuation from frozen JSON",
    )
    value_parser.add_argument("input", type=Path)

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    payload = load_json(args.input)
    if args.command == "hash-manifest":
        output: Any = {"input_hash": manifest_hash(payload)}
    elif args.command == "validate-contract":
        output = validate_contract_payload(payload)
    elif args.command == "value":
        output = value_payload(payload)
    else:  # pragma: no cover - argparse enforces valid commands.
        parser.error(f"unknown command: {args.command}")
    print(json.dumps(output, ensure_ascii=False, sort_keys=True, indent=2))
    return 0
