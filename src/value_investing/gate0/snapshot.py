from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime
from hashlib import sha256
import json
from typing import Iterable


@dataclass(frozen=True, slots=True)
class FinancialFact:
    issuer_code: str
    statement_scope: str
    metric_code: str
    period_start: str | None
    period_end: str
    value: str
    unit: str | None
    currency: str | None
    available_at: datetime
    revision_no: int = 1
    source_document_id: str | None = None
    source_fact_key: str | None = None

    @property
    def business_key(self) -> tuple[str, str, str, str | None, str]:
        return (
            self.issuer_code,
            self.statement_scope,
            self.metric_code,
            self.period_start,
            self.period_end,
        )


def _require_aware(value: datetime) -> None:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("PIT timestamps must be timezone-aware")


def select_latest_as_of(
    facts: Iterable[FinancialFact], cutoff: datetime
) -> list[FinancialFact]:
    """Select the latest eligible revision known at cutoff for each fact key."""
    _require_aware(cutoff)
    selected: dict[tuple[str, str, str, str | None, str], FinancialFact] = {}
    for fact in facts:
        _require_aware(fact.available_at)
        if fact.available_at > cutoff:
            continue
        current = selected.get(fact.business_key)
        if current is None or (fact.available_at, fact.revision_no) > (
            current.available_at,
            current.revision_no,
        ):
            selected[fact.business_key] = fact
    return sorted(selected.values(), key=lambda item: item.business_key)


def build_snapshot_manifest(
    facts: Iterable[FinancialFact], cutoff: datetime, policy_version: str
) -> tuple[dict[str, object], str]:
    selected = select_latest_as_of(facts, cutoff)
    rows: list[dict[str, object]] = []
    for fact in selected:
        row = asdict(fact)
        row["available_at"] = fact.available_at.isoformat()
        rows.append(row)
    manifest: dict[str, object] = {
        "cutoff": cutoff.isoformat(),
        "cutoff_policy_version": policy_version,
        "fact_count": len(rows),
        "facts": rows,
    }
    canonical = json.dumps(
        manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return manifest, sha256(canonical).hexdigest()
