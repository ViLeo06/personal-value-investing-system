from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from value_investing.availability import SSE_SZSE_AVAILABILITY


SHANGHAI = ZoneInfo("Asia/Shanghai")


def next_monday_open(_published):
    return datetime(2021, 8, 2, 9, 30, tzinfo=SHANGHAI)


def test_after_close_friday_is_available_next_session():
    published = datetime(2021, 7, 30, 19, 34, tzinfo=SHANGHAI)
    usable = SSE_SZSE_AVAILABILITY.earliest_usable_at(
        published, next_session_open=next_monday_open
    )
    assert usable == datetime(2021, 8, 2, 9, 30, tzinfo=SHANGHAI)


def test_pre_open_release_is_available_at_open():
    published = datetime(2021, 7, 30, 7, 0, tzinfo=SHANGHAI)
    usable = SSE_SZSE_AVAILABILITY.earliest_usable_at(
        published, next_session_open=next_monday_open
    )
    assert usable == datetime(2021, 7, 30, 9, 30, tzinfo=SHANGHAI)


def test_intraday_release_keeps_exact_time():
    published = datetime(2021, 7, 30, 11, 0, tzinfo=SHANGHAI)
    usable = SSE_SZSE_AVAILABILITY.earliest_usable_at(
        published, next_session_open=next_monday_open
    )
    assert usable == published


def test_naive_timestamp_is_rejected():
    with pytest.raises(ValueError):
        SSE_SZSE_AVAILABILITY.earliest_usable_at(
            datetime(2021, 7, 30, 19, 34),
            next_session_open=next_monday_open,
        )
