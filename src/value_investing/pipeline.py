from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime
from hashlib import sha256
import json
from typing import Any, Mapping, Sequence

from value_investing.model_router import ModelRoute, route_model


class PipelineControlError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class DataGateResult:
    passed: bool
    missing: tuple[str, ...]
    null_or_nonfinite: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class RunManifest:
    issuer_code: str
    security_code: str | None
    as_of_at: str
    snapshot_hash: str
    snapshot_policy_version: str
    model_family: str
    model_module: str
    model_version: str
    scenario_set_version: str
    parameter_hash: str
    code_commit_sha: str | None
    dependency_lock_hash: str | None
    trading_calendar_version: str | None
    corporate_action_version: str | None
    benchmark_policy_version: str | None
    transaction_cost_policy_version: str | None

    @property
    def run_hash(self) -> str:
        return content_hash(asdict(self))


@dataclass(frozen=True, slots=True)
class FrozenPhaseA:
    manifest: RunManifest
    assumptions: Mapping[str, Any]
    data_quality: DataGateResult
    frozen_at: str
    payload_hash: str


def canonical_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    )


def content_hash(value: Any) -> str:
    return sha256(canonical_json(value).encode("utf-8")).hexdigest()


def evaluate_data_gate(
    values: Mapping[str, Any], required_fields: Sequence[str]
) -> DataGateResult:
    missing = sorted(field for field in required_fields if field not in values)
    invalid: list[str] = []
    for field in required_fields:
        if field not in values:
            continue
        value = values[field]
        if value is None:
            invalid.append(field)
            continue
        if isinstance(value, float) and (value != value or value in (float("inf"), float("-inf"))):
            invalid.append(field)
    invalid = sorted(set(invalid))
    return DataGateResult(
        passed=not missing and not invalid,
        missing=tuple(missing),
        null_or_nonfinite=tuple(invalid),
    )


def build_run_manifest(
    *,
    issuer_code: str,
    security_code: str | None,
    as_of_at: datetime,
    snapshot_hash: str,
    snapshot_policy_version: str,
    model_family: str,
    model_version: str,
    scenario_set_version: str,
    parameters: Mapping[str, Any],
    code_commit_sha: str | None = None,
    dependency_lock_hash: str | None = None,
    trading_calendar_version: str | None = None,
    corporate_action_version: str | None = None,
    benchmark_policy_version: str | None = None,
    transaction_cost_policy_version: str | None = None,
) -> RunManifest:
    if as_of_at.tzinfo is None or as_of_at.utcoffset() is None:
        raise PipelineControlError("as_of_at must be timezone-aware")
    if len(snapshot_hash) != 64:
        raise PipelineControlError("snapshot_hash must be a SHA-256 hex digest")
    route: ModelRoute = route_model(model_family)
    return RunManifest(
        issuer_code=issuer_code,
        security_code=security_code,
        as_of_at=as_of_at.isoformat(),
        snapshot_hash=snapshot_hash,
        snapshot_policy_version=snapshot_policy_version,
        model_family=model_family,
        model_module=route.primary_module,
        model_version=model_version,
        scenario_set_version=scenario_set_version,
        parameter_hash=content_hash(parameters),
        code_commit_sha=code_commit_sha,
        dependency_lock_hash=dependency_lock_hash,
        trading_calendar_version=trading_calendar_version,
        corporate_action_version=corporate_action_version,
        benchmark_policy_version=benchmark_policy_version,
        transaction_cost_policy_version=transaction_cost_policy_version,
    )


def freeze_phase_a(
    *,
    manifest: RunManifest,
    assumptions: Mapping[str, Any],
    data_quality: DataGateResult,
    frozen_at: datetime,
) -> FrozenPhaseA:
    if frozen_at.tzinfo is None or frozen_at.utcoffset() is None:
        raise PipelineControlError("frozen_at must be timezone-aware")
    if not data_quality.passed:
        raise PipelineControlError(
            "Phase A cannot be frozen as completed while required data are missing"
        )
    payload = {
        "manifest": asdict(manifest),
        "assumptions": assumptions,
        "data_quality": asdict(data_quality),
        "frozen_at": frozen_at.isoformat(),
    }
    return FrozenPhaseA(
        manifest=manifest,
        assumptions=dict(assumptions),
        data_quality=data_quality,
        frozen_at=frozen_at.isoformat(),
        payload_hash=content_hash(payload),
    )


def verify_phase_a_replay(frozen: FrozenPhaseA) -> bool:
    payload = {
        "manifest": asdict(frozen.manifest),
        "assumptions": frozen.assumptions,
        "data_quality": asdict(frozen.data_quality),
        "frozen_at": frozen.frozen_at,
    }
    return content_hash(payload) == frozen.payload_hash
