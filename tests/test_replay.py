from datetime import datetime, timezone

import pytest

from value_investing.replay import SnapshotItem, assert_pit_cutoff, membership_hash


def test_membership_hash_is_order_independent():
    first = SnapshotItem("pit.financial_facts", "stable-key-2", "b")
    second = SnapshotItem("pit.financial_facts", "stable-key-1", "a")
    assert membership_hash([first, second]) == membership_hash([second, first])


def test_membership_hash_does_not_depend_on_database_row_id():
    left = SnapshotItem(
        "pit.financial_facts", "issuer|revenue|2020-12-31|r1", "hash", input_id="12"
    )
    right = SnapshotItem(
        "pit.financial_facts", "issuer|revenue|2020-12-31|r1", "hash", input_id="987"
    )
    assert membership_hash([left]) == membership_hash([right])


def test_cutoff_rejects_future_input():
    cutoff = datetime(2021, 4, 1, tzinfo=timezone.utc)
    with pytest.raises(ValueError, match="post-cutoff"):
        assert_pit_cutoff(
            [
                SnapshotItem(
                    "pit.financial_facts",
                    "issuer|revenue|2020-12-31|r2",
                    "a",
                    datetime(2021, 4, 2, tzinfo=timezone.utc),
                )
            ],
            cutoff,
        )
