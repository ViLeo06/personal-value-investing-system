"""Immutable analytical-cache manifest helpers."""
from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import PurePosixPath
import re
from typing import Iterable, Sequence

from .hashing import sha256_hex


_PARTITION_VALUE = re.compile(r"^[A-Za-z0-9_.-]+$")


@dataclass(frozen=True)
class CacheFile:
    path: str
    row_count: int
    content_hash: str


@dataclass(frozen=True)
class CacheManifest:
    dataset_name: str
    schema_version: str
    source_snapshot_hash: str
    exported_at: datetime
    key_columns: tuple[str, ...]
    files: tuple[CacheFile, ...]
    minimum_available_at: datetime | None = None
    maximum_available_at: datetime | None = None

    @property
    def row_count(self) -> int:
        return sum(file.row_count for file in self.files)

    @property
    def manifest_hash(self) -> str:
        return sha256_hex(asdict(self))


def partition_path(dataset: str, **partitions: str | int) -> str:
    if not dataset or dataset.startswith("/") or ".." in PurePosixPath(dataset).parts:
        raise ValueError("dataset must be a safe relative path")
    parts = [dataset.strip("/")]
    for key, raw_value in partitions.items():
        value = str(raw_value)
        if not key or not _PARTITION_VALUE.fullmatch(key):
            raise ValueError(f"unsafe partition key: {key!r}")
        if not _PARTITION_VALUE.fullmatch(value):
            raise ValueError(f"unsafe partition value for {key}: {value!r}")
        parts.append(f"{key}={value}")
    return str(PurePosixPath(*parts))


def validate_cache_manifest(manifest: CacheManifest) -> None:
    if manifest.exported_at.tzinfo is None:
        raise ValueError("export timestamp must be timezone-aware")
    if not manifest.dataset_name or not manifest.schema_version:
        raise ValueError("dataset name and schema version are required")
    if len(manifest.source_snapshot_hash) != 64:
        raise ValueError("source snapshot hash must be a SHA-256 hex digest")
    if not manifest.key_columns:
        raise ValueError("at least one key column is required")
    if not manifest.files:
        raise ValueError("at least one cache file is required")
    paths = [file.path for file in manifest.files]
    if len(paths) != len(set(paths)):
        raise ValueError("cache file paths must be unique")
    for file in manifest.files:
        if file.row_count < 0:
            raise ValueError("row counts cannot be negative")
        if len(file.content_hash) != 64:
            raise ValueError("file content hashes must be SHA-256 digests")
        if file.path.startswith("/") or ".." in PurePosixPath(file.path).parts:
            raise ValueError("cache files must use safe relative paths")
    if (
        manifest.minimum_available_at is not None
        and manifest.maximum_available_at is not None
        and manifest.minimum_available_at > manifest.maximum_available_at
    ):
        raise ValueError("minimum availability cannot exceed maximum availability")
    if manifest.minimum_available_at and manifest.minimum_available_at.tzinfo is None:
        raise ValueError("minimum availability must be timezone-aware")
    if manifest.maximum_available_at and manifest.maximum_available_at.tzinfo is None:
        raise ValueError("maximum availability must be timezone-aware")


def ordered_key_hash(rows: Iterable[Sequence[object]]) -> str:
    """Hash already ordered business-key rows for PostgreSQL/Parquet checks."""
    return sha256_hex([list(row) for row in rows])
