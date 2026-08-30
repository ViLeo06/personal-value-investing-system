from datetime import datetime, timezone

import pytest

from value_investing.cache import (
    CacheFile,
    CacheManifest,
    ordered_key_hash,
    partition_path,
    validate_cache_manifest,
)


HASH_A = "a" * 64
HASH_B = "b" * 64


def test_partition_path_is_stable_and_safe():
    assert partition_path(
        "pit/market_bars", schema="v1", exchange="XSHG", trade_year=2021
    ) == "pit/market_bars/schema=v1/exchange=XSHG/trade_year=2021"
    with pytest.raises(ValueError):
        partition_path("pit/market_bars", issuer="../../secret")


def test_cache_manifest_validation_and_hash():
    manifest = CacheManifest(
        dataset_name="pit.financial_facts",
        schema_version="v1",
        source_snapshot_hash=HASH_A,
        exported_at=datetime(2026, 8, 30, tzinfo=timezone.utc),
        key_columns=("issuer_id", "metric_code", "period_end", "available_at"),
        files=(CacheFile("pit/facts/part-000.parquet", 13, HASH_B),),
        minimum_available_at=datetime(2021, 3, 31, tzinfo=timezone.utc),
        maximum_available_at=datetime(2021, 8, 2, tzinfo=timezone.utc),
    )
    validate_cache_manifest(manifest)
    assert manifest.row_count == 13
    assert len(manifest.manifest_hash) == 64


def test_ordered_key_hash_depends_on_order():
    first = ordered_key_hash([(1, "a"), (2, "b")])
    second = ordered_key_hash([(2, "b"), (1, "a")])
    assert first != second
