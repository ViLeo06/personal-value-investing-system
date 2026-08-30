from datetime import datetime, timezone

import pytest

from value_investing.release import (
    ArtifactReference,
    ReleaseManifest,
    capture_dependency_versions,
    capture_environment,
    freeze_release,
)


UTC = timezone.utc
HASH_A = "a" * 64
HASH_B = "b" * 64
HASH_C = "c" * 64


def manifest() -> ReleaseManifest:
    return ReleaseManifest(
        release_tag="v1.2.0-gate0-dev",
        git_commit_sha="1" * 40,
        created_at=datetime(2026, 8, 30, 10, 0, tzinfo=UTC),
        migration_versions=("202608300003", "202608300001", "202608300002"),
        seed_versions=("009", "007", "008"),
        model_versions={
            "owner_earnings_dcf": "1.0.0",
            "fcff_sotp": "1.0.0",
        },
        parameter_set_hashes=(HASH_B, HASH_A),
        data_snapshot_hashes=(HASH_C,),
        quality_rule_set_hash=HASH_A,
        dependency_versions={"pytest": "8.0.0", "python": "3.12"},
        environment={"platform": "test", "python_version": "3.12"},
        artifacts=(
            ArtifactReference("reports/b.md", HASH_B, "text/markdown"),
            ArtifactReference("reports/a.json", HASH_A, "application/json"),
        ),
    )


def test_release_hash_is_canonical():
    first = manifest()
    second = ReleaseManifest(
        release_tag=first.release_tag,
        git_commit_sha=first.git_commit_sha,
        created_at=first.created_at,
        migration_versions=tuple(reversed(first.migration_versions)),
        seed_versions=tuple(reversed(first.seed_versions)),
        model_versions=dict(reversed(tuple(first.model_versions.items()))),
        parameter_set_hashes=tuple(reversed(first.parameter_set_hashes)),
        data_snapshot_hashes=first.data_snapshot_hashes,
        quality_rule_set_hash=first.quality_rule_set_hash,
        dependency_versions=dict(
            reversed(tuple(first.dependency_versions.items()))
        ),
        environment=dict(reversed(tuple(first.environment.items()))),
        artifacts=tuple(reversed(first.artifacts)),
    )
    assert first.manifest_hash() == second.manifest_hash()


def test_freeze_requires_valid_time_and_changes_manifest_hash():
    draft = manifest()
    draft_hash = draft.manifest_hash()
    frozen = freeze_release(
        draft,
        frozen_at=datetime(2026, 8, 30, 11, 0, tzinfo=UTC),
    )
    assert frozen.status == "frozen"
    assert frozen.manifest_hash() != draft_hash
    with pytest.raises(ValueError):
        freeze_release(frozen, frozen_at=frozen.frozen_at)


def test_invalid_commit_or_hash_fails():
    invalid = manifest()
    invalid = ReleaseManifest(
        **{
            **invalid.__dict__,
            "git_commit_sha": "not-a-commit",
        }
    )
    with pytest.raises(ValueError):
        invalid.manifest_hash()

    with pytest.raises(ValueError):
        ArtifactReference("report.md", "bad").validate()


def test_environment_capture_is_allowlisted_and_dependency_capture_is_total():
    environment = capture_environment()
    assert "python_version" in environment
    assert not any("secret" in key.lower() for key in environment)
    versions = capture_dependency_versions(
        ["definitely-not-installed-package-for-test", "pytest"]
    )
    assert versions["definitely-not-installed-package-for-test"] == "not-installed"
    assert versions["pytest"] != "not-installed"
