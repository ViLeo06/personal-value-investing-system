"""Financial-statement parser contracts.

Parsers convert immutable evidence bytes into source-faithful facts. They do
not normalize accounting policy differences or make valuation judgments.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal
from enum import Enum
from typing import Mapping, Protocol, Sequence


class FactKind(str, Enum):
    INSTANT = "instant"
    DURATION = "duration"


@dataclass(frozen=True)
class ParsedFact:
    statement_type: str
    metric_code: str
    period_end: date
    fact_kind: FactKind
    value_numeric: Decimal | None = None
    value_text: str | None = None
    metric_label: str | None = None
    period_start: date | None = None
    fiscal_year: int | None = None
    fiscal_period: str | None = None
    statement_scope: str = "consolidated"
    unit: str | None = None
    currency: str | None = None
    scale: Decimal = Decimal("1")
    source_fact_key: str | None = None
    metadata: Mapping[str, object] | None = None

    def validate(self) -> None:
        if not self.statement_type or not self.metric_code:
            raise ValueError("statement_type and metric_code are required")
        if (self.value_numeric is None) == (self.value_text is None):
            raise ValueError("exactly one of value_numeric/value_text is required")
        if self.scale <= 0:
            raise ValueError("scale must be positive")
        if self.fact_kind is FactKind.DURATION:
            if self.period_start is None:
                raise ValueError("duration facts require period_start")
            if self.period_start > self.period_end:
                raise ValueError("period_start cannot follow period_end")
        elif self.period_start is not None and self.period_start != self.period_end:
            raise ValueError("instant facts cannot span a duration")

    def canonical_payload(self) -> dict[str, object]:
        self.validate()
        return {
            "statement_type": self.statement_type,
            "metric_code": self.metric_code,
            "metric_label": self.metric_label,
            "period_start": (
                self.period_start.isoformat() if self.period_start else None
            ),
            "period_end": self.period_end.isoformat(),
            "fiscal_year": self.fiscal_year,
            "fiscal_period": self.fiscal_period,
            "statement_scope": self.statement_scope,
            "fact_kind": self.fact_kind.value,
            "value_numeric": (
                str(self.value_numeric) if self.value_numeric is not None else None
            ),
            "value_text": self.value_text,
            "unit": self.unit,
            "currency": self.currency,
            "scale": str(self.scale),
            "source_fact_key": self.source_fact_key,
            "metadata": dict(self.metadata or {}),
        }

    def fact_hash(self) -> str:
        encoded = json.dumps(
            self.canonical_payload(),
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        return hashlib.sha256(encoded).hexdigest()


@dataclass(frozen=True)
class ParserResult:
    document_sha256: str
    parser_name: str
    parser_version: str
    facts: tuple[ParsedFact, ...]
    warnings: tuple[str, ...] = ()
    metadata: Mapping[str, object] | None = None

    def validate(self) -> None:
        if len(self.document_sha256) != 64:
            raise ValueError("document_sha256 must contain 64 hex characters")
        if not self.parser_name or not self.parser_version:
            raise ValueError("parser_name and parser_version are required")
        natural_keys: set[tuple[object, ...]] = set()
        for fact in self.facts:
            fact.validate()
            key = (
                fact.statement_scope,
                fact.statement_type,
                fact.metric_code,
                fact.period_start,
                fact.period_end,
                fact.fact_kind,
                fact.source_fact_key,
            )
            if key in natural_keys:
                raise ValueError(f"duplicate parsed fact natural key: {key}")
            natural_keys.add(key)

    def result_hash(self) -> str:
        self.validate()
        payload = {
            "document_sha256": self.document_sha256.lower(),
            "parser_name": self.parser_name,
            "parser_version": self.parser_version,
            "facts": [
                fact.canonical_payload()
                for fact in sorted(
                    self.facts,
                    key=lambda item: (
                        item.statement_scope,
                        item.statement_type,
                        item.metric_code,
                        item.period_start or item.period_end,
                        item.period_end,
                        item.source_fact_key or "",
                    ),
                )
            ],
            "warnings": sorted(self.warnings),
            "metadata": dict(self.metadata or {}),
        }
        encoded = json.dumps(
            payload,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        return hashlib.sha256(encoded).hexdigest()

    def to_pit_rows(
        self,
        *,
        issuer_id: str,
        source_document_id: str,
        published_at: datetime | None,
        available_at: datetime,
        revision_no: int = 1,
        is_preliminary: bool = False,
    ) -> tuple[dict[str, object], ...]:
        self.validate()
        if available_at.tzinfo is None:
            raise ValueError("available_at must be timezone-aware")
        if published_at is not None and published_at.tzinfo is None:
            raise ValueError("published_at must be timezone-aware")
        if published_at is not None and available_at < published_at:
            raise ValueError("available_at cannot precede published_at")
        if revision_no <= 0:
            raise ValueError("revision_no must be positive")
        return tuple(
            {
                "issuer_id": issuer_id,
                "statement_scope": fact.statement_scope,
                "statement_type": fact.statement_type,
                "metric_code": fact.metric_code,
                "metric_label": fact.metric_label,
                "period_start": (
                    fact.period_start.isoformat() if fact.period_start else None
                ),
                "period_end": fact.period_end.isoformat(),
                "fiscal_year": fact.fiscal_year,
                "fiscal_period": fact.fiscal_period,
                "fact_kind": fact.fact_kind.value,
                "value_numeric": (
                    str(fact.value_numeric)
                    if fact.value_numeric is not None
                    else None
                ),
                "value_text": fact.value_text,
                "unit": fact.unit,
                "currency": fact.currency,
                "scale": str(fact.scale),
                "published_at": (
                    published_at.isoformat() if published_at else None
                ),
                "available_at": available_at.isoformat(),
                "revision_no": revision_no,
                "is_preliminary": is_preliminary,
                "source_document_id": source_document_id,
                "source_fact_key": fact.source_fact_key,
                "record_hash": fact.fact_hash(),
                "metadata": {
                    "document_sha256": self.document_sha256,
                    "parser_name": self.parser_name,
                    "parser_version": self.parser_version,
                    "parser_result_hash": self.result_hash(),
                    **dict(fact.metadata or {}),
                },
            }
            for fact in self.facts
        )


class FinancialStatementParser(Protocol):
    parser_name: str
    parser_version: str

    def parse(
        self,
        content: bytes,
        *,
        document_sha256: str,
        metadata: Mapping[str, object],
    ) -> ParserResult: ...
