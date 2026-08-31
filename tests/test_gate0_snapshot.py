from datetime import datetime, timezone

from value_investing.gate0.snapshot import FinancialFact, build_snapshot_manifest, select_latest_as_of


def fact(value: str, available: str, revision: int) -> FinancialFact:
    return FinancialFact(
        issuer_code="TEST",
        statement_scope="consolidated",
        metric_code="revenue",
        period_start="2020-01-01",
        period_end="2020-12-31",
        value=value,
        unit="CNY",
        currency="CNY",
        available_at=datetime.fromisoformat(available),
        revision_no=revision,
    )


def test_future_revision_does_not_leak() -> None:
    rows = [
        fact("100", "2021-03-31T00:00:00+00:00", 1),
        fact("110", "2021-05-01T00:00:00+00:00", 2),
    ]
    cutoff = datetime(2021, 4, 1, tzinfo=timezone.utc)
    selected = select_latest_as_of(rows, cutoff)
    assert len(selected) == 1
    assert selected[0].value == "100"


def test_manifest_hash_is_order_independent() -> None:
    rows = [
        fact("100", "2021-03-31T00:00:00+00:00", 1),
        FinancialFact(
            issuer_code="TEST",
            statement_scope="consolidated",
            metric_code="net_income_parent",
            period_start="2020-01-01",
            period_end="2020-12-31",
            value="20",
            unit="CNY",
            currency="CNY",
            available_at=datetime(2021, 3, 31, tzinfo=timezone.utc),
        ),
    ]
    cutoff = datetime(2021, 4, 1, tzinfo=timezone.utc)
    _, first = build_snapshot_manifest(rows, cutoff, "pit_cutoff_v1")
    _, second = build_snapshot_manifest(reversed(rows), cutoff, "pit_cutoff_v1")
    assert first == second
