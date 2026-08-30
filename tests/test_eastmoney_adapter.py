from datetime import date
from urllib.parse import parse_qs, urlparse

import pytest

from value_investing.adapters.eastmoney import build_kline_url, parse_kline_payload


PAYLOAD = {
    "rc": 0,
    "data": {
        "code": "600519",
        "market": 1,
        "name": "贵州茅台",
        "klines": [
            "2021-03-31,2000.00,2010.00,2025.00,1988.00,12345,2469000000,1.84,0.50,10.00,0.98",
            "2021-04-01,2015.00,2022.00,2030.00,2001.00,12000,2430000000,1.44,0.60,12.00,0.95",
        ],
    },
}


def test_build_url_forces_unadjusted_daily_data():
    url = build_kline_url("600519.SH", date(2021, 3, 31), date(2021, 4, 1))
    query = parse_qs(urlparse(url).query)
    assert query["secid"] == ["1.600519"]
    assert query["klt"] == ["101"]
    assert query["fqt"] == ["0"]
    assert query["beg"] == ["20210331"]
    assert query["end"] == ["20210401"]


def test_parse_payload_normalizes_price_and_availability():
    bars = parse_kline_payload(PAYLOAD, "600519.SH")
    assert len(bars) == 2
    first = bars[0]
    assert first.trade_date == date(2021, 3, 31)
    assert first.close_price == pytest.approx(2010.0)
    assert first.previous_close == pytest.approx(2000.0)
    assert first.available_at.isoformat() == "2021-03-31T15:00:00+08:00"
    assert first.adjustment == "unadjusted"
    assert len(first.record_hash) == 32


def test_rejects_non_a_share_code():
    with pytest.raises(ValueError, match="supports"):
        build_kline_url("0700.HK", date(2021, 3, 31), date(2021, 4, 1))
