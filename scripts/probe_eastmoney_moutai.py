#!/usr/bin/env python3
"""Fetch a narrow, auditable Moutai market-data evidence bundle.

This is a source adapter/probe, not part of the valuation domain model. It tries
free public market endpoints in a fixed order, filters only dates required by
the Gate-0 total-return ledger, and records every request attempt plus SHA-256
hashes of successful raw responses and selected raw rows.

Provider order:

1. Eastmoney daily K-line endpoint with ``fqt=0`` (unadjusted).
2. Yahoo Finance chart endpoint, using ``quote.close`` rather than adjusted
   close for the unadjusted security-price series.

The resulting bundle remains secondary/derived evidence. It does not become an
exchange-authoritative record merely because it is machine-readable.
"""
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

EASTMONEY_BASE_URL = "https://push2his.eastmoney.com/api/qt/stock/kline/get"
YAHOO_BASE_URL = "https://query1.finance.yahoo.com/v8/finance/chart/600519.SS"
SHANGHAI = ZoneInfo("Asia/Shanghai")
TARGET_DATES = {
    "2021-08-30",  # Phase-A decision close
    "2022-06-30",
    "2022-12-27",
    "2023-06-30",
    "2023-12-20",
    "2024-06-19",
    "2024-12-20",
    "2025-06-26",
    "2025-12-19",
    "2026-06-26",
    "2026-08-28",  # five-year Phase-B endpoint
}
KNOWN_ANCHORS = {
    "2021-08-30": 1586.0,
    "2026-08-28": 1297.4,
}
OUTPUT = Path("artifacts/market_probes/moutai_gate0_public_market_probe.json")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def fetch_bytes(url: str, *, referer: str) -> tuple[bytes, int, str | None]:
    request = Request(
        url,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                "(KHTML, like Gecko) Chrome/151.0 Safari/537.36"
            ),
            "Referer": referer,
            "Accept": "application/json,text/plain,*/*",
            "Accept-Language": "en-US,en;q=0.9,zh-CN;q=0.8",
        },
    )
    with urlopen(request, timeout=30) as response:  # noqa: S310 - fixed HTTPS hosts
        raw = response.read()
        return raw, response.status, response.headers.get("Content-Type")


def parse_eastmoney_kline(line: str) -> dict[str, object]:
    fields = line.split(",")
    if len(fields) != 11:
        raise ValueError(f"unexpected Eastmoney K-line field count: {len(fields)}")
    return {
        "trade_date": fields[0],
        "open": float(fields[1]),
        "close": float(fields[2]),
        "high": float(fields[3]),
        "low": float(fields[4]),
        "volume": float(fields[5]),
        "volume_unit": "lots",
        "turnover_cny": float(fields[6]),
        "amplitude_pct": float(fields[7]),
        "change_pct": float(fields[8]),
        "change_cny": float(fields[9]),
        "turnover_rate_pct": float(fields[10]),
        "raw_row": line,
        "raw_row_sha256": sha256_bytes(line.encode("utf-8")),
    }


def eastmoney_probe() -> dict[str, Any]:
    params = {
        "secid": "1.600519",
        "fields1": "f1,f2,f3,f4,f5,f6",
        "fields2": "f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61",
        "klt": "101",
        "fqt": "0",
        "beg": "20210830",
        "end": "20260828",
        "lmt": "2000",
    }
    url = f"{EASTMONEY_BASE_URL}?{urlencode(params)}"
    raw, status, content_type = fetch_bytes(
        url,
        referer="https://quote.eastmoney.com/sh600519.html",
    )
    payload = json.loads(raw.decode("utf-8"))
    data = payload.get("data") or {}
    klines = data.get("klines") or []
    selected = {
        row["trade_date"]: row
        for row in map(parse_eastmoney_kline, klines)
        if row["trade_date"] in TARGET_DATES
    }
    return {
        "provider": "eastmoney_public_kline",
        "security_name": data.get("name"),
        "currency": "CNY",
        "request": {
            "url": url,
            "parameters": params,
            "http_status": status,
            "content_type": content_type,
            "response_sha256": sha256_bytes(raw),
        },
        "selected": selected,
    }


def yahoo_probe() -> dict[str, Any]:
    period1 = int(datetime(2021, 8, 29, tzinfo=timezone.utc).timestamp())
    period2 = int(datetime(2026, 8, 30, tzinfo=timezone.utc).timestamp())
    params = {
        "period1": str(period1),
        "period2": str(period2),
        "interval": "1d",
        "events": "history",
        "includeAdjustedClose": "true",
    }
    url = f"{YAHOO_BASE_URL}?{urlencode(params)}"
    raw, status, content_type = fetch_bytes(
        url,
        referer="https://finance.yahoo.com/quote/600519.SS/history/",
    )
    payload = json.loads(raw.decode("utf-8"))
    chart = payload.get("chart") or {}
    if chart.get("error"):
        raise RuntimeError(f"Yahoo chart error: {chart['error']}")
    results = chart.get("result") or []
    if not results:
        raise RuntimeError("Yahoo chart returned no result")
    result = results[0]
    timestamps = result.get("timestamp") or []
    quote_groups = ((result.get("indicators") or {}).get("quote") or [])
    if not quote_groups:
        raise RuntimeError("Yahoo chart returned no quote group")
    quote = quote_groups[0]
    opens = quote.get("open") or []
    closes = quote.get("close") or []
    highs = quote.get("high") or []
    lows = quote.get("low") or []
    volumes = quote.get("volume") or []
    lengths = {len(timestamps), len(opens), len(closes), len(highs), len(lows), len(volumes)}
    if len(lengths) != 1:
        raise RuntimeError(f"Yahoo chart arrays have unequal lengths: {sorted(lengths)}")

    selected: dict[str, dict[str, object]] = {}
    for timestamp, open_price, close, high, low, volume in zip(
        timestamps,
        opens,
        closes,
        highs,
        lows,
        volumes,
        strict=True,
    ):
        if close is None:
            continue
        trade_date = datetime.fromtimestamp(timestamp, tz=SHANGHAI).date().isoformat()
        if trade_date not in TARGET_DATES:
            continue
        raw_row = json.dumps(
            {
                "timestamp": timestamp,
                "open": open_price,
                "close": close,
                "high": high,
                "low": low,
                "volume": volume,
            },
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        selected[trade_date] = {
            "trade_date": trade_date,
            "open": float(open_price) if open_price is not None else None,
            "close": float(close),
            "high": float(high) if high is not None else None,
            "low": float(low) if low is not None else None,
            "volume": float(volume) if volume is not None else None,
            "volume_unit": "shares",
            "turnover_cny": None,
            "raw_row": raw_row,
            "raw_row_sha256": sha256_bytes(raw_row.encode("utf-8")),
        }

    meta = result.get("meta") or {}
    return {
        "provider": "yahoo_public_chart",
        "security_name": meta.get("shortName") or meta.get("symbol"),
        "currency": meta.get("currency") or "CNY",
        "request": {
            "url": url,
            "parameters": params,
            "http_status": status,
            "content_type": content_type,
            "response_sha256": sha256_bytes(raw),
        },
        "selected": selected,
    }


def validate_selected(selected: dict[str, dict[str, object]]) -> None:
    missing = sorted(TARGET_DATES - selected.keys())
    if missing:
        raise RuntimeError(f"missing target dates: {missing}")
    for trade_date, expected_close in KNOWN_ANCHORS.items():
        actual_close = float(selected[trade_date]["close"])
        if abs(actual_close - expected_close) > 0.011:
            raise RuntimeError(
                f"anchor mismatch on {trade_date}: expected {expected_close}, got {actual_close}"
            )


def main() -> None:
    providers: tuple[tuple[str, Callable[[], dict[str, Any]]], ...] = (
        ("eastmoney_public_kline", eastmoney_probe),
        ("yahoo_public_chart", yahoo_probe),
    )
    attempts: list[dict[str, object]] = []
    successful: dict[str, Any] | None = None

    for provider_name, probe in providers:
        try:
            candidate = probe()
            validate_selected(candidate["selected"])
            attempts.append(
                {
                    "provider": provider_name,
                    "status": "success",
                    "request": candidate["request"],
                }
            )
            successful = candidate
            break
        except Exception as exc:  # each free endpoint gets one auditable attempt
            attempts.append(
                {
                    "provider": provider_name,
                    "status": "failure",
                    "error_type": type(exc).__name__,
                    "error": str(exc),
                }
            )

    if successful is None:
        raise RuntimeError(
            "all market-data providers failed: "
            + json.dumps(attempts, ensure_ascii=False, sort_keys=True)
        )

    selected = successful.pop("selected")
    result = {
        "schema_version": "public_market_probe_v2",
        "evidence_level": "public_secondary_crosscheck",
        "authoritative_exchange_record": False,
        "provider": successful["provider"],
        "security_code": "600519.SH",
        "security_name": successful["security_name"],
        "currency": successful["currency"],
        "price_adjustment": "unadjusted",
        "attempts": attempts,
        "successful_request": successful["request"],
        "target_dates": sorted(TARGET_DATES),
        "rows": [selected[trade_date] for trade_date in sorted(selected)],
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    canonical = json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2)
    OUTPUT.write_text(canonical + "\n", encoding="utf-8")
    print(canonical)


if __name__ == "__main__":
    main()
