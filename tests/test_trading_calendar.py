from datetime import date

import pytest

from value_investing.trading_calendar import (
    TradingCalendar,
    TradingDay,
    build_calendar_version,
)


HASH = "a" * 64


def calendar():
    version = build_calendar_version(
        exchange_mic="XSHG",
        version="xshg-2021-gate0",
        valid_from=date(2021, 8, 27),
        valid_to=date(2021, 9, 1),
        source_code="SSE",
        source_document_hash=HASH,
        frozen=True,
        days=(
            TradingDay(date(2021, 8, 27), True, date(2021, 8, 27)),
            TradingDay(date(2021, 8, 28), False),
            TradingDay(date(2021, 8, 29), False),
            TradingDay(date(2021, 8, 30), True, date(2021, 8, 30)),
            TradingDay(date(2021, 8, 31), True, date(2021, 8, 31)),
            TradingDay(date(2021, 9, 1), True, date(2021, 9, 1)),
        ),
    )
    return TradingCalendar(version)


def test_next_previous_and_range_are_frozen_calendar_queries():
    cal = calendar()
    assert cal.next_open(date(2021, 8, 27)) == date(2021, 8, 30)
    assert cal.next_open(date(2021, 8, 28), inclusive=True) == date(2021, 8, 30)
    assert cal.previous_open(date(2021, 8, 30)) == date(2021, 8, 27)
    assert cal.previous_open(date(2021, 8, 30), inclusive=True) == date(2021, 8, 30)
    assert cal.open_dates(date(2021, 8, 28), date(2021, 8, 31)) == (
        date(2021, 8, 30),
        date(2021, 8, 31),
    )


def test_closed_or_out_of_range_queries_fail_loudly():
    cal = calendar()
    assert cal.is_open(date(2021, 8, 28)) is False
    with pytest.raises(ValueError):
        cal.is_open(date(2021, 8, 26))
    with pytest.raises(ValueError):
        cal.settlement_date(date(2021, 8, 28))
    with pytest.raises(ValueError):
        cal.next_open(date(2021, 9, 1))


def test_calendar_hash_is_stable_and_sensitive_to_content():
    first = calendar().version
    second = build_calendar_version(
        exchange_mic=first.exchange_mic,
        version=first.version,
        valid_from=first.valid_from,
        valid_to=first.valid_to,
        source_code=first.source_code,
        source_document_hash=first.source_document_hash,
        frozen=True,
        days=tuple(reversed(first.days)),
    )
    assert first.content_hash() == second.content_hash()

    changed = build_calendar_version(
        exchange_mic=first.exchange_mic,
        version=first.version,
        valid_from=first.valid_from,
        valid_to=first.valid_to,
        source_code=first.source_code,
        source_document_hash=first.source_document_hash,
        frozen=True,
        days=first.days[:-1]
        + (TradingDay(date(2021, 9, 1), False),),
    )
    assert first.content_hash() != changed.content_hash()


def test_invalid_calendar_rows_are_rejected():
    with pytest.raises(ValueError):
        build_calendar_version(
            exchange_mic="XHKG",
            version="bad",
            valid_from=date(2021, 1, 1),
            valid_to=date(2021, 1, 2),
            source_code="HKEX",
            source_document_hash=HASH,
            days=(TradingDay(date(2020, 12, 31), True),),
        )
    with pytest.raises(ValueError):
        TradingDay(
            date(2021, 1, 2),
            True,
            settlement_date=date(2021, 1, 1),
        ).validate()
