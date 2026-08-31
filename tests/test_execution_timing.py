from datetime import date, datetime, timezone
from decimal import Decimal

from value_investing.backtest.execution import decision_and_execution_prices
from value_investing.data.market import MarketBar


def bar(day: date, open_price: str, close_price: str, available: datetime) -> MarketBar:
    open_value = Decimal(open_price)
    close_value = Decimal(close_price)
    return MarketBar(
        security_code="TEST.SH",
        trade_date=day,
        open_price=open_value,
        high_price=max(open_value, close_value),
        low_price=min(open_value, close_value),
        close_price=close_value,
        volume=None,
        turnover=None,
        currency="CNY",
        available_at=available,
        retrieved_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
        source_code="TEST",
        record_hash=day.isoformat(),
    )


def test_decision_does_not_use_same_day_close() -> None:
    decision_at = datetime(2021, 4, 1, 0, 0, tzinfo=timezone.utc)
    rows = [
        bar(
            date(2021, 3, 31),
            "100",
            "101",
            datetime(2021, 3, 31, 7, 15, tzinfo=timezone.utc),
        ),
        bar(
            date(2021, 4, 1),
            "102",
            "110",
            datetime(2021, 4, 1, 7, 15, tzinfo=timezone.utc),
        ),
    ]
    context = decision_and_execution_prices(rows, decision_at)
    assert context.reference_close == Decimal("101")
    assert context.execution_open == Decimal("102")
    assert context.execution_open != Decimal("110")
