from dataclasses import dataclass
from datetime import datetime, timezone

import pytest

from value_investing.pit import PitCutoff, assert_no_future_leakage, eligible_records


@dataclass(frozen=True)
class Record:
    value: int
    available_at: datetime


def test_pit_cutoff_is_inclusive_and_timezone_aware():
    cutoff = PitCutoff(datetime(2021, 8, 30, 8, tzinfo=timezone.utc))
    records = [
        Record(1, datetime(2021, 8, 30, 7, 59, tzinfo=timezone.utc)),
        Record(2, cutoff.decision_at),
        Record(3, datetime(2021, 8, 30, 8, 1, tzinfo=timezone.utc)),
    ]
    assert [r.value for r in eligible_records(records, cutoff)] == [1, 2]
    with pytest.raises(ValueError, match="PIT leakage"):
        assert_no_future_leakage(records, cutoff)


def test_naive_timestamps_are_rejected():
    cutoff = PitCutoff(datetime(2021, 8, 30, 8, tzinfo=timezone.utc))
    with pytest.raises(ValueError, match="timezone-aware"):
        cutoff.eligible(datetime(2021, 8, 30, 8))
