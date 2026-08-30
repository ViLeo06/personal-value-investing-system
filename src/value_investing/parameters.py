"""Versioned scenario parameter sets.

Parameter sets separate analyst judgment and empirical priors from model code.
Frozen sets are content-addressed and cannot be edited in place.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from math import isfinite
from typing import Iterable, Mapping


class ParameterSource(str, Enum):
    REPORTED_FACT = "reported_fact"
    NORMALIZED_FACT = "normalized_fact"
    EMPIRICAL_PRIOR = "empirical_prior"
    ANALYST_JUDGMENT = "analyst_judgment"
    POLICY = "policy"


@dataclass(frozen=True)
class ParameterValue:
    scenario: str
    key: str
    value: float | str | bool | tuple[object, ...]
    unit: str | None
    source: ParameterSource
    provenance: Mapping[str, object]

    def validate(self) -> None:
        if not self.scenario:
            raise ValueError("scenario cannot be empty")
        if not self.key:
            raise ValueError("parameter key cannot be empty")
        if isinstance(self.value, float) and not isfinite(self.value):
            raise ValueError(f"parameter {self.key} must be finite")


@dataclass(frozen=True)
class ScenarioMonotonicRule:
    key: str
    order: tuple[str, ...] = ("pessimistic", "base", "optimistic")
    increasing: bool = True


@dataclass(frozen=True)
class ParameterSet:
    model_family: str
    version: str
    effective_from: datetime
    values: tuple[ParameterValue, ...]
    issuer_code: str | None = None
    source_snapshot_id: str | None = None
    frozen_at: datetime | None = None
    notes: str | None = None

    def validate(
        self,
        *,
        required_keys: Iterable[str] = (),
        monotonic_rules: Iterable[ScenarioMonotonicRule] = (),
    ) -> None:
        if not self.model_family or not self.version:
            raise ValueError("model_family and version are required")
        if self.effective_from.tzinfo is None:
            raise ValueError("effective_from must be timezone-aware")
        if self.frozen_at is not None and self.frozen_at.tzinfo is None:
            raise ValueError("frozen_at must be timezone-aware")
        if self.frozen_at is not None and self.frozen_at < self.effective_from:
            raise ValueError("frozen_at cannot precede effective_from")

        identities: set[tuple[str, str]] = set()
        by_scenario: dict[str, dict[str, ParameterValue]] = {}
        for value in self.values:
            value.validate()
            identity = (value.scenario, value.key)
            if identity in identities:
                raise ValueError(
                    f"duplicate parameter: {value.scenario}/{value.key}"
                )
            identities.add(identity)
            by_scenario.setdefault(value.scenario, {})[value.key] = value

        required = set(required_keys)
        for scenario in sorted(by_scenario):
            missing = required - by_scenario[scenario].keys()
            if missing:
                raise ValueError(
                    f"scenario {scenario} is missing required keys: "
                    f"{sorted(missing)}"
                )

        for rule in monotonic_rules:
            selected: list[float] = []
            for scenario in rule.order:
                try:
                    raw = by_scenario[scenario][rule.key].value
                except KeyError as exc:
                    raise ValueError(
                        f"monotonic rule {rule.key} requires scenario {scenario}"
                    ) from exc
                if not isinstance(raw, (int, float)) or isinstance(raw, bool):
                    raise ValueError(
                        f"monotonic parameter {rule.key} must be numeric"
                    )
                selected.append(float(raw))
            pairs = zip(selected, selected[1:], strict=False)
            valid = all(
                left <= right if rule.increasing else left >= right
                for left, right in pairs
            )
            if not valid:
                direction = "increasing" if rule.increasing else "decreasing"
                raise ValueError(
                    f"parameter {rule.key} is not {direction} across {rule.order}"
                )

    def canonical_payload(self) -> dict[str, object]:
        values = [
            {
                "scenario": item.scenario,
                "key": item.key,
                "value": item.value,
                "unit": item.unit,
                "source": item.source.value,
                "provenance": dict(item.provenance),
            }
            for item in sorted(self.values, key=lambda item: (item.scenario, item.key))
        ]
        return {
            "model_family": self.model_family,
            "version": self.version,
            "effective_from": self.effective_from.isoformat(),
            "issuer_code": self.issuer_code,
            "source_snapshot_id": self.source_snapshot_id,
            "frozen_at": self.frozen_at.isoformat() if self.frozen_at else None,
            "notes": self.notes,
            "values": values,
        }

    def content_hash(self) -> str:
        encoded = json.dumps(
            self.canonical_payload(),
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
        return hashlib.sha256(encoded).hexdigest()

    @property
    def is_frozen(self) -> bool:
        return self.frozen_at is not None


def freeze_parameter_set(
    parameter_set: ParameterSet,
    frozen_at: datetime,
) -> ParameterSet:
    if parameter_set.is_frozen:
        raise ValueError("parameter set is already frozen")
    frozen = ParameterSet(
        model_family=parameter_set.model_family,
        version=parameter_set.version,
        effective_from=parameter_set.effective_from,
        values=parameter_set.values,
        issuer_code=parameter_set.issuer_code,
        source_snapshot_id=parameter_set.source_snapshot_id,
        frozen_at=frozen_at,
        notes=parameter_set.notes,
    )
    frozen.validate()
    return frozen
