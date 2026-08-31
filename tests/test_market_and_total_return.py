from datetime import date, datetime, timezone
from decimal import Decimal

from value_investing.backtest.total_return import cash_total_return
from value_investing.data.market import (
    CorporateAction,
    derived_daily_availability,
    parse_eastmoney_kline_payload,
)


def test_kline_normalization_and_availability() -> None:
    payload = {"data": {"klines": ["2021-04-01,100,102,103,99,12345,987654"]}}
    rows = parse_eastmoney_kline_payload(
        payload,
        security_code="TEST.SH",
        exchange_mic="XSHG",
        currency="CNY",
        retrieved_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )
    assert rows[0].close_price == Decimal("102")
    assert rows[0].available_at == derived_daily_availability(date(2021, 4, 1), "XSHG")
    assert len(rows[0].record_hash) == 64


def test_cash_dividend_receivable_prevents_ex_date_artificial_loss() -> None:
    action = CorporateAction(
        security_code="TEST.SH",
        action_type="cash_dividend",
        available_at=datetime(2021, 1, 1, tzinfo=timezone.utc),
        ex_date=date(2021, 1, 2),
        payment_date=date(2021, 1, 3),
        cash_amount_per_share=Decimal("5"),
        currency="CNY",
    )
    result = cash_total_return(
        initial_quantity=Decimal("10"),
        prices={
            date(2021, 1, 1): Decimal("100"),
            date(2021, 1, 2): Decimal("95"),
            date(2021, 1, 3): Decimal("95"),
        },
        actions=[action],
    )
    assert result.ledger[1].nav == Decimal("1000")
    assert result.ending_nav == Decimal("1000")
    assert result.total_return == Decimal("0")


def test_split_preserves_value_when_price_adjusts() -> None:
    action = CorporateAction(
        security_code="TEST.SH",
        action_type="split",
        available_at=datetime(2021, 1, 1, tzinfo=timezone.utc),
        effective_date=date(2021, 1, 2),
        ratio_numerator=Decimal("2"),
        ratio_denominator=Decimal("1"),
    )
    result = cash_total_return(
        initial_quantity=Decimal("10"),
        prices={date(2021, 1, 1): Decimal("100"), date(2021, 1, 2): Decimal("50")},
        actions=[action],
    )
    assert result.ending_nav == Decimal("1000")
    assert result.total_return == Decimal("0")
