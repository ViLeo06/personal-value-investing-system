"""Thin adapter for Eastmoney's public daily-kline endpoint.

This source is free but not treated as an authoritative native PIT source. Raw
responses, adapter version, adjustment mode and record hashes must be retained,
and critical samples should be cross-checked against an exchange or another
independent source.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import date, datetime, time
from hashlib import md5
import json
from typing import Any, Iterable
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo


ADAPTER_VERSION = "eastmoney_kline_v1"
ENDPOINT = "https://push2his.eastmoney.com/api/qt/stock/kline/get"
FIELDS1 = "f1,f2,f3,f4,f5,f6"
FIELDS2 = "f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61"
SHANGHAI = ZoneInfo("Asia/Shanghai")


@dataclass(frozen=True, slots=True)
class DailyBar:
    security_code: str
    trade_date: date
    open_price: float
    high_price: float
    low_price: float
    close_price: float
    previous_close: float
    volume: float
    turnover: float
    currency: str
    available_at: datetime
    source_code: str
    adapter_version: str
    adjustment: str
    record_hash: str
    metadata: dict[str, Any]

    def to_dict(self) -> dict[str, Any]:
        value = asdict(self)
        value["trade_date"] = self.trade_date.isoformat()
        value["available_at"] = self.available_at.isoformat()
        return value


def _secid(security_code: str) -> str:
    normalized = security_code.upper().strip()
    if normalized.endswith(".SH"):
        ticker = normalized[:-3]
        market = "1"
    elif normalized.endswith(".SZ"):
        ticker = normalized[:-3]
        market = "0"
    else:
        raise ValueError("this adapter currently supports .SH and .SZ securities only")
    if len(ticker) != 6 or not ticker.isdigit():
        raise ValueError(f"invalid A-share security code: {security_code}")
    return f"{market}.{ticker}"


def build_kline_url(
    security_code: str,
    begin: date,
    end: date,
    *,
    unadjusted: bool = True,
) -> str:
    if begin > end:
        raise ValueError("begin must not be after end")
    parameters = {
        "secid": _secid(security_code),
        "klt": "101",
        "fqt": "0" if unadjusted else "1",
        "beg": begin.strftime("%Y%m%d"),
        "end": end.strftime("%Y%m%d"),
        "fields1": FIELDS1,
        "fields2": FIELDS2,
    }
    return f"{ENDPOINT}?{urlencode(parameters)}"


def _record_hash(security_code: str, fields: Iterable[str]) -> str:
    payload = "|".join((security_code, *fields, "EASTMONEY_PUBLIC_API", "unadjusted"))
    return md5(payload.encode("utf-8"), usedforsecurity=False).hexdigest()


def parse_kline_payload(payload: dict[str, Any], security_code: str) -> tuple[DailyBar, ...]:
    data = payload.get("data")
    if not isinstance(data, dict):
        raise ValueError("response does not contain a data object")
    lines = data.get("klines")
    if not isinstance(lines, list):
        raise ValueError("response does not contain a kline array")

    bars: list[DailyBar] = []
    for raw in lines:
        if not isinstance(raw, str):
            raise ValueError("kline entry must be a string")
        fields = raw.split(",")
        if len(fields) < 11:
            raise ValueError(f"unexpected kline field count: {len(fields)}")
        trade_date = date.fromisoformat(fields[0])
        close_price = float(fields[2])
        price_change = float(fields[9])
        bars.append(
            DailyBar(
                security_code=security_code.upper(),
                trade_date=trade_date,
                open_price=float(fields[1]),
                close_price=close_price,
                high_price=float(fields[3]),
                low_price=float(fields[4]),
                previous_close=close_price - price_change,
                volume=float(fields[5]),
                turnover=float(fields[6]),
                currency="CNY",
                available_at=datetime.combine(trade_date, time(15, 0), SHANGHAI),
                source_code="EASTMONEY_PUBLIC_API",
                adapter_version=ADAPTER_VERSION,
                adjustment="unadjusted",
                record_hash=_record_hash(security_code.upper(), fields[:11]),
                metadata={
                    "change_percent": float(fields[8]),
                    "turnover_rate": float(fields[10]),
                    "raw_line": raw,
                },
            )
        )
    return tuple(bars)


def fetch_daily_bars(
    security_code: str,
    begin: date,
    end: date,
    *,
    timeout_seconds: float = 20.0,
) -> tuple[DailyBar, ...]:
    """Fetch unadjusted bars; callers are responsible for raw-response archival."""

    url = build_kline_url(security_code, begin, end, unadjusted=True)
    request = Request(url, headers={"User-Agent": "value-investing-valuation-system/0.1"})
    with urlopen(request, timeout=timeout_seconds) as response:  # noqa: S310 - fixed HTTPS host
        if response.status != 200:
            raise RuntimeError(f"market-data request failed with HTTP {response.status}")
        raw = response.read()
    payload = json.loads(raw.decode("utf-8"))
    if payload.get("rc") not in (0, None):
        raise RuntimeError(f"market-data provider returned rc={payload.get('rc')}")
    return parse_kline_payload(payload, security_code)
