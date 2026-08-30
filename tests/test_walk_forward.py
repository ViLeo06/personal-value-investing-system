from dataclasses import dataclass
from datetime import date, datetime, timezone

import pytest

from value_investing.walk_forward import (
    DecisionPoint,
    HistoricalMembership,
    eligible_universe,
    freeze_records,
    run_walk_forward,
)


@dataclass(frozen=True)
class Record:
    available_at: datetime
    fingerprint: str
    value: float


def test_historical_universe_avoids_current_constituent_bias():
    memberships = [
        HistoricalMembership("OLD", date(2010, 1, 1), date(2020, 12, 31)),
        HistoricalMembership("NEW", date(2021, 1, 1)),
    ]
    assert eligible_universe(memberships, date(2020, 6, 30)) == ("OLD",)
    assert eligible_universe(memberships, date(2021, 6, 30)) == ("NEW",)


def test_freeze_rejects_future_information():
    decision = DecisionPoint(
        datetime(2021, 8, 30, 7, 0, tzinfo=timezone.utc), "2021H2"
    )
    records = [
        Record(datetime(2021, 8, 30, 6, 0, tzinfo=timezone.utc), "known", 1.0),
        Record(datetime(2021, 8, 31, 6, 0, tzinfo=timezone.utc), "future", 2.0),
    ]
    with pytest.raises(ValueError, match="PIT leakage"):
        freeze_records(
            decision,
            "TEST",
            records,
            record_fingerprint=lambda record: record.fingerprint,
        )


def test_walk_forward_is_deterministic():
    decisions = [
        DecisionPoint(datetime(2020, 6, 30, tzinfo=timezone.utc), "2020H1"),
        DecisionPoint(datetime(2021, 6, 30, tzinfo=timezone.utc), "2021H1"),
    ]
    memberships = [
        HistoricalMembership("OLD", date(2010, 1, 1), date(2020, 12, 31)),
        HistoricalMembership("NEW", date(2021, 1, 1)),
    ]
    store = {
        "OLD": [Record(datetime(2020, 1, 1, tzinfo=timezone.utc), "old-1", 3.0)],
        "NEW": [Record(datetime(2021, 1, 1, tzinfo=timezone.utc), "new-1", 4.0)],
    }

    def load_records(security_code, cutoff):
        return [
            record
            for record in store[security_code]
            if record.available_at <= cutoff.decision_at
        ]

    def evaluate(security_code, decision, records):
        return sum(record.value for record in records)

    kwargs = dict(
        decision_points=decisions,
        memberships=memberships,
        load_records=load_records,
        evaluate=evaluate,
        record_fingerprint=lambda record: record.fingerprint,
        model_version="test-model@1",
    )
    first = run_walk_forward(**kwargs)
    second = run_walk_forward(**kwargs)
    assert first == second
    assert [(row.security_code, row.result) for row in first] == [
        ("OLD", 3.0),
        ("NEW", 4.0),
    ]
