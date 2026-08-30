"""Source-neutral contracts for free/open data adapters."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from math import isfinite
from typing import Mapping, Sequence


@dataclass(frozen=True)
class DataSourcePolicy:
    source_code: str
    is_free: bool
    is_open_source: bool
    pit_capability: str
    authoritative_roles: tuple[str, ...] = ()


@dataclass(frozen=True)
class AdapterBatch:
    source_code: str
    adapter_version: str
    started_at: datetime
    completed_at: datetime
    request_parameters: Mapping[str, object]
    batch_hash: str


@dataclass(frozen=True)
class AdapterDocument:
    stable_key: str
    document_type: str
    title: str
    source_url: str
    published_at: datetime | None
    available_at: datetime | None
    effective_date: date | None
    content_hash: str | None
    publication_precision: str
    evidence_quality: str
    metadata: Mapping[str, object]


@dataclass(frozen=True)
class AdapterFact:
    issuer_code: str
    statement_type: str
    metric_code: str
    period_start: date | None
    period_end: date
    value_numeric: float | None
    value_text: str | None
    unit: str | None
    currency: str | None
    published_at: datetime | None
    available_at: datetime
    revision_no: int
    source_document_key: str | None
    source_fact_key: str
    record_hash: str
    metadata: Mapping[str, object]


@dataclass(frozen=True)
class AdapterResult:
    policy: DataSourcePolicy
    batch: AdapterBatch
    documents: Sequence[AdapterDocument]
    facts: Sequence[AdapterFact]


def validate_adapter_result(result: AdapterResult) -> None:
    if not result.policy.is_free:
        raise ValueError("paid data sources are outside the project data policy")
    if result.policy.pit_capability not in {"native", "derived", "none", "unknown"}:
        raise ValueError("invalid PIT capability")
    if result.batch.started_at.tzinfo is None or result.batch.completed_at.tzinfo is None:
        raise ValueError("batch timestamps must be timezone-aware")
    if result.batch.completed_at < result.batch.started_at:
        raise ValueError("batch completion cannot precede start")
    if len(result.batch.batch_hash) != 64:
        raise ValueError("batch hash must be a SHA-256 digest")

    document_keys = [document.stable_key for document in result.documents]
    if len(document_keys) != len(set(document_keys)):
        raise ValueError("document stable keys must be unique within a batch")
    for document in result.documents:
        if not document.stable_key or not document.document_type or not document.source_url:
            raise ValueError("document key, type and URL are required")
        if document.published_at and document.published_at.tzinfo is None:
            raise ValueError("document publication timestamps must be timezone-aware")
        if document.available_at and document.available_at.tzinfo is None:
            raise ValueError("document availability timestamps must be timezone-aware")
        if (
            document.published_at
            and document.available_at
            and document.available_at < document.published_at
        ):
            raise ValueError("document availability cannot precede publication")
        if document.content_hash is not None and len(document.content_hash) != 64:
            raise ValueError("document content hash must be SHA-256")

    fact_hashes = [fact.record_hash for fact in result.facts]
    if len(fact_hashes) != len(set(fact_hashes)):
        raise ValueError("fact hashes must be unique within a batch")
    known_documents = set(document_keys)
    for fact in result.facts:
        if fact.available_at.tzinfo is None:
            raise ValueError("fact availability must be timezone-aware")
        if fact.published_at and fact.published_at.tzinfo is None:
            raise ValueError("fact publication timestamps must be timezone-aware")
        if fact.published_at and fact.available_at < fact.published_at:
            raise ValueError("fact availability cannot precede publication")
        if (fact.value_numeric is None) == (fact.value_text is None):
            raise ValueError("each fact must have exactly one numeric or text value")
        if fact.value_numeric is not None and not isfinite(fact.value_numeric):
            raise ValueError("numeric facts must be finite")
        if fact.revision_no < 1:
            raise ValueError("fact revision number must be positive")
        if len(fact.record_hash) != 64:
            raise ValueError("fact record hash must be SHA-256")
        if fact.source_document_key and fact.source_document_key not in known_documents:
            raise ValueError("fact references an unknown document key")
