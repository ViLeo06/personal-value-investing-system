"""Deterministic research release manifests."""
from __future__ import annotations

import hashlib
import json
import platform
import re
import sys
from dataclasses import dataclass
from datetime import datetime
from importlib import metadata
from typing import Iterable, Mapping


_COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")
_HASH_PATTERN = re.compile(r"^[0-9a-f]{64}$")


@dataclass(frozen=True)
class ArtifactReference:
    path: str
    sha256: str
    media_type: str | None = None

    def validate(self) -> None:
        if not self.path:
            raise ValueError("artifact path cannot be empty")
        if not _HASH_PATTERN.fullmatch(self.sha256.lower()):
            raise ValueError(f"invalid SHA-256 for artifact {self.path}")


@dataclass(frozen=True)
class ReleaseManifest:
    release_tag: str
    git_commit_sha: str
    created_at: datetime
    migration_versions: tuple[str, ...]
    seed_versions: tuple[str, ...]
    model_versions: Mapping[str, str]
    parameter_set_hashes: tuple[str, ...]
    data_snapshot_hashes: tuple[str, ...]
    quality_rule_set_hash: str
    dependency_versions: Mapping[str, str]
    environment: Mapping[str, str]
    artifacts: tuple[ArtifactReference, ...] = ()
    status: str = "draft"
    frozen_at: datetime | None = None

    def validate(self) -> None:
        if not self.release_tag:
            raise ValueError("release_tag is required")
        if not _COMMIT_PATTERN.fullmatch(self.git_commit_sha.lower()):
            raise ValueError("git_commit_sha must contain 40 lowercase hex digits")
        if self.created_at.tzinfo is None:
            raise ValueError("created_at must be timezone-aware")
        if self.frozen_at is not None and self.frozen_at.tzinfo is None:
            raise ValueError("frozen_at must be timezone-aware")
        if self.status not in {"draft", "frozen", "retired"}:
            raise ValueError(f"unsupported release status: {self.status}")
        if self.status == "frozen" and self.frozen_at is None:
            raise ValueError("a frozen release requires frozen_at")
        if tuple(sorted(set(self.migration_versions))) != tuple(
            sorted(self.migration_versions)
        ):
            raise ValueError("migration versions must be unique")
        if tuple(sorted(set(self.seed_versions))) != tuple(
            sorted(self.seed_versions)
        ):
            raise ValueError("seed versions must be unique")
        for label, hashes in (
            ("parameter set", self.parameter_set_hashes),
            ("data snapshot", self.data_snapshot_hashes),
        ):
            for value in hashes:
                if not _HASH_PATTERN.fullmatch(value.lower()):
                    raise ValueError(f"invalid {label} SHA-256: {value}")
        if not _HASH_PATTERN.fullmatch(self.quality_rule_set_hash.lower()):
            raise ValueError("quality_rule_set_hash must be a SHA-256")
        for artifact in self.artifacts:
            artifact.validate()

    def canonical_payload(self) -> dict[str, object]:
        return {
            "release_tag": self.release_tag,
            "git_commit_sha": self.git_commit_sha.lower(),
            "created_at": self.created_at.isoformat(),
            "migration_versions": sorted(self.migration_versions),
            "seed_versions": sorted(self.seed_versions),
            "model_versions": dict(sorted(self.model_versions.items())),
            "parameter_set_hashes": sorted(self.parameter_set_hashes),
            "data_snapshot_hashes": sorted(self.data_snapshot_hashes),
            "quality_rule_set_hash": self.quality_rule_set_hash.lower(),
            "dependency_versions": dict(
                sorted(self.dependency_versions.items())
            ),
            "environment": dict(sorted(self.environment.items())),
            "artifacts": [
                {
                    "path": artifact.path,
                    "sha256": artifact.sha256.lower(),
                    "media_type": artifact.media_type,
                }
                for artifact in sorted(self.artifacts, key=lambda item: item.path)
            ],
            "status": self.status,
            "frozen_at": self.frozen_at.isoformat() if self.frozen_at else None,
        }

    def manifest_hash(self) -> str:
        self.validate()
        encoded = json.dumps(
            self.canonical_payload(),
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
        return hashlib.sha256(encoded).hexdigest()


def capture_environment() -> dict[str, str]:
    """Capture a safe, non-secret runtime environment summary."""
    return {
        "python_version": platform.python_version(),
        "python_implementation": platform.python_implementation(),
        "platform_system": platform.system(),
        "platform_release": platform.release(),
        "platform_machine": platform.machine(),
        "byteorder": sys.byteorder,
    }


def capture_dependency_versions(
    package_names: Iterable[str],
) -> dict[str, str]:
    versions: dict[str, str] = {}
    for package_name in sorted(set(package_names)):
        try:
            versions[package_name] = metadata.version(package_name)
        except metadata.PackageNotFoundError:
            versions[package_name] = "not-installed"
    return versions


def freeze_release(
    manifest: ReleaseManifest,
    *,
    frozen_at: datetime,
) -> ReleaseManifest:
    if manifest.status == "frozen":
        raise ValueError("release is already frozen")
    frozen = ReleaseManifest(
        release_tag=manifest.release_tag,
        git_commit_sha=manifest.git_commit_sha,
        created_at=manifest.created_at,
        migration_versions=manifest.migration_versions,
        seed_versions=manifest.seed_versions,
        model_versions=manifest.model_versions,
        parameter_set_hashes=manifest.parameter_set_hashes,
        data_snapshot_hashes=manifest.data_snapshot_hashes,
        quality_rule_set_hash=manifest.quality_rule_set_hash,
        dependency_versions=manifest.dependency_versions,
        environment=manifest.environment,
        artifacts=manifest.artifacts,
        status="frozen",
        frozen_at=frozen_at,
    )
    frozen.validate()
    return frozen
