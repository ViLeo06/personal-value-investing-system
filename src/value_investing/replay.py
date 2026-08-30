"""Canonical helpers for materialized point-in-time snapshot membership."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from hashlib import md5
from typing import Iterable


@dataclass(frozen=True, slots=True)
class SnapshotItem:
    input_type: str
    input_key: str
    input_hash: str | None
    source_available_at: datetime | None = None
    input_id: str | None = None


def membership_hash(items: Iterable[SnapshotItem]) -> str:
    """Match the database's stable_input_key_v1 membership digest."""

    ordered = sorted(items, key=lambda item: (item.input_type, item.input_key))
    payload = "||".join(
        "|".join((item.input_type, item.input_key, item.input_hash or ""))
        for item in ordered
    )
    return md5(payload.encode("utf-8"), usedforsecurity=False).hexdigest()


def assert_pit_cutoff(items: Iterable[SnapshotItem], cutoff: datetime) -> None:
    """Reject any source row that was unavailable at the decision cutoff."""

    leaks = [
        item
        for item in items
        if item.source_available_at is not None and item.source_available_at > cutoff
    ]
    if leaks:
        identifiers = ", ".join(
            f"{item.input_type}:{item.input_key}" for item in leaks[:5]
        )
        raise ValueError(f"snapshot contains post-cutoff inputs: {identifiers}")
