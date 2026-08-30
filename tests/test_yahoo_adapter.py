from datetime import date
from urllib.parse import parse_qs, urlparse

import pytest

from value_investing.adapters.yahoo import build_chart_url, parse_chart_payload


PAYLOAD = {
    "chart": {
        "error": None,
        "result": [
            {
                "meta": {
                    "currency": "CNY",
                    "exchangeTimezoneName": "Asia/Shanghai",
                },
                "timestamp": [1617174000, 1617260400],
                "indicators": {
                    "quote": [
                        {
                            "open": [10.0, 10.5],
                            "high": [10.6, 11.0],
                            "low": [9.9, 10.4],
                            "close": [10.5, 10.8],
                            "volume": [1000, 1200],
                        }
                    ],
                    "adjclose": [{"adjclose": [10.2, 10.8]}],
                },
                "events": {
                    "dividends": {
                        "1617174000": {
                            "amount": 0.2,
                            "date": 1617174000,
                        }
                    },
                    "splits": {
                        "1617260400": {
                            "date": 1617260400,
                            "numerator": 2.0,
                            "denominator": 1.0,
                        }
                    },
                },
            }
        ],
    }
}


def test_build_chart_url_has_daily_events_and_exclusive_end():
    url = build_chart_url("600519.SS", date(2021, 3, 31), date(2021, 4, 2))
    query = parse_qs(urlparse(url).query)
    assert query["interval"] == ["1d"]
    assert query["events"] == ["div,splits"]
    assert int(query["period2"][0]) > int(query["period1"][0])


def test_parse_chart_normalizes_bars_and_events():
    result = parse_chart_payload(PAYLOAD, "600519.SS")
    assert result.currency == "CNY"
    assert len(result.bars) == 2
    assert result.bars[0].previous_close is None
    assert result.bars[1].previous_close == pytest.approx(10.5)
    assert result.bars[0].available_at.utcoffset().total_seconds() == 8 * 3600
    assert len(result.dividends) == 1
    assert result.dividends[0].amount_per_share == pytest.approx(0.2)
    assert len(result.splits) == 1
    assert result.splits[0].numerator / result.splits[0].denominator == pytest.approx(2.0)


def test_provider_error_is_not_silently_ignored():
    payload = {"chart": {"error": {"code": "Bad Request"}, "result": None}}
    with pytest.raises(RuntimeError, match="provider error"):
        parse_chart_payload(payload, "600519.SS")
