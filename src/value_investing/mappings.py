"""Versioned source-label to canonical-metric mappings."""
from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from typing import Iterable


_WHITESPACE = re.compile(r"\s+")


def normalize_source_label(label: str) -> str:
    normalized = unicodedata.normalize("NFKC", label).strip().casefold()
    return _WHITESPACE.sub(" ", normalized)


@dataclass(frozen=True)
class MappingRule:
    source_code: str
    source_label: str
    canonical_metric_code: str
    statement_type: str
    statement_scope: str = "consolidated"
    valid_from: date | None = None
    valid_to: date | None = None
    output_unit: str | None = None
    output_currency: str | None = None
    scale_multiplier: Decimal = Decimal("1")
    sign_multiplier: Decimal = Decimal("1")
    priority: int = 100
    notes: str | None = None

    def validate(self) -> None:
        if not self.source_code or not self.source_label:
            raise ValueError("source_code and source_label are required")
        if not self.canonical_metric_code or not self.statement_type:
            raise ValueError("canonical metric and statement type are required")
        if self.valid_from and self.valid_to and self.valid_to < self.valid_from:
            raise ValueError("valid_to cannot precede valid_from")
        if self.scale_multiplier <= 0:
            raise ValueError("scale_multiplier must be positive")
        if self.sign_multiplier not in {Decimal("-1"), Decimal("1")}:
            raise ValueError("sign_multiplier must be -1 or 1")

    @property
    def normalized_label(self) -> str:
        return normalize_source_label(self.source_label)

    def active_on(self, period_end: date) -> bool:
        return (
            (self.valid_from is None or self.valid_from <= period_end)
            and (self.valid_to is None or period_end <= self.valid_to)
        )

    def convert_numeric(
        self,
        value: Decimal,
        *,
        source_scale: Decimal = Decimal("1"),
    ) -> Decimal:
        self.validate()
        if source_scale <= 0:
            raise ValueError("source_scale must be positive")
        return (
            value
            * source_scale
            * self.scale_multiplier
            * self.sign_multiplier
        )


@dataclass(frozen=True)
class MappingRegistry:
    source_code: str
    version: str
    rules: tuple[MappingRule, ...]
    frozen: bool = False

    def validate(self) -> None:
        if not self.source_code or not self.version:
            raise ValueError("source_code and version are required")
        identities: set[tuple[object, ...]] = set()
        for rule in self.rules:
            rule.validate()
            if rule.source_code != self.source_code:
                raise ValueError("registry contains a rule from another source")
            identity = (
                rule.normalized_label,
                rule.statement_type,
                rule.statement_scope,
                rule.valid_from,
                rule.valid_to,
                rule.priority,
            )
            if identity in identities:
                raise ValueError(f"duplicate mapping-rule identity: {identity}")
            identities.add(identity)

    def resolve(
        self,
        source_label: str,
        *,
        statement_type: str,
        statement_scope: str,
        period_end: date,
    ) -> MappingRule:
        self.validate()
        label = normalize_source_label(source_label)
        candidates = [
            rule
            for rule in self.rules
            if rule.normalized_label == label
            and rule.statement_type == statement_type
            and rule.statement_scope == statement_scope
            and rule.active_on(period_end)
        ]
        if not candidates:
            raise KeyError(
                f"no mapping for {self.source_code}/{source_label!r}/"
                f"{statement_type}/{statement_scope} on {period_end}"
            )
        best_priority = min(rule.priority for rule in candidates)
        best = [rule for rule in candidates if rule.priority == best_priority]
        canonical_codes = {rule.canonical_metric_code for rule in best}
        if len(best) != 1 or len(canonical_codes) != 1:
            raise ValueError(
                f"ambiguous mapping for label {source_label!r}: {best}"
            )
        return best[0]

    def content_hash(self) -> str:
        self.validate()
        payload = {
            "source_code": self.source_code,
            "version": self.version,
            "rules": [
                {
                    "source_label": rule.source_label,
                    "normalized_label": rule.normalized_label,
                    "canonical_metric_code": rule.canonical_metric_code,
                    "statement_type": rule.statement_type,
                    "statement_scope": rule.statement_scope,
                    "valid_from": (
                        rule.valid_from.isoformat() if rule.valid_from else None
                    ),
                    "valid_to": (
                        rule.valid_to.isoformat() if rule.valid_to else None
                    ),
                    "output_unit": rule.output_unit,
                    "output_currency": rule.output_currency,
                    "scale_multiplier": str(rule.scale_multiplier),
                    "sign_multiplier": str(rule.sign_multiplier),
                    "priority": rule.priority,
                    "notes": rule.notes,
                }
                for rule in sorted(
                    self.rules,
                    key=lambda item: (
                        item.normalized_label,
                        item.statement_type,
                        item.statement_scope,
                        item.valid_from or date.min,
                        item.priority,
                        item.canonical_metric_code,
                    ),
                )
            ],
            "frozen": self.frozen,
        }
        encoded = json.dumps(
            payload,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        return hashlib.sha256(encoded).hexdigest()


def build_registry(
    source_code: str,
    version: str,
    rules: Iterable[MappingRule],
    *,
    frozen: bool = False,
) -> MappingRegistry:
    registry = MappingRegistry(
        source_code=source_code,
        version=version,
        rules=tuple(rules),
        frozen=frozen,
    )
    registry.validate()
    return registry
