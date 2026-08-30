"""Canonical hashing utilities for reproducible research manifests."""
from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, is_dataclass
from datetime import date, datetime
from decimal import Decimal
from enum import Enum
from typing import Any


def _json_default(value: Any) -> Any:
    if is_dataclass(value):
        return asdict(value)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return format(value, "f")
    if isinstance(value, Enum):
        return value.value
    raise TypeError(f"Unsupported canonical JSON value: {type(value)!r}")


def canonical_json(value: Any) -> str:
    """Serialize with stable key ordering and no insignificant whitespace."""
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
        default=_json_default,
    )


def sha256_hex(value: Any) -> str:
    """Hash canonical JSON or raw bytes with SHA-256."""
    payload = value if isinstance(value, bytes) else canonical_json(value).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()
