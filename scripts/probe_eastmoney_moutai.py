#!/usr/bin/env python3
"""Fetch a narrow, auditable Moutai market-data evidence bundle.

This is a source adapter/probe, not part of the valuation domain model. It uses
Eastmoney's unauthenticated public daily K-line endpoint with fqt=0 (unadjusted),
filters only dates required by the Gate-0 total-return ledger, and records the
request URL plus SHA-256 hashes. The output remains secondary/derived evidence;
it does not become an exchange-authoritative record merely because it is
machine-readable.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

BASE_URL = "https://push2his.eastmoney.com/api/qt/stock/kline/get"
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
PARAMS = {
    "secid": "1.600519",
    "fields1": "f1,f2,f3,f4,f5,f6",
    "fields2": "f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61",
    "klt": "101",
    "fqt": "0",
    "beg": "20210830",
    "end": "20260828",
    "lmt": "2000",
}
OUTPUT = Path("artifacts/market_probes/moutai_gate0_eastmoney.json")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def parse_kline(line: str) -> dict[str, object]:
    fields = line.split(",")
    if len(fields) != 11:
        raise ValueError(f"unexpected kline field count: {len(fields)}")
    return {
        "trade_date": fields[0],
        "open": float(fields[1]),
        "close": float(fields[2]),
        "high": float(fields[3]),
        "low": float(fields[4]),
        "volume_lots": float(fields[5]),
        "turnover_cny": float(fields[6]),
        "amplitude_pct": float(fields[7]),
        "change_pct": float(fields[8]),
        "change_cny": float(fields[9]),
        "turnover_rate_pct": float(fields[10]),
        "raw_line": line,
        "raw_line_sha256": sha256_bytes(line.encode("utf-8")),
    }


def main() -> None:
    request_url = f"{BASE_URL}?{urlencode(PARAMS)}"
    request = Request(
        request_url,
        headers={
            "User-Agent": "Mozilla/5.0 (compatible; VIVS-Gate0/1.0)",
            "Referer": "https://quote.eastmoney.com/sh600519.html",
            "Accept": "application/json,text/plain,*/*",
        },
    )
    with urlopen(request, timeout=30) as response:  # noqa: S310 - fixed HTTPS host
        raw = response.read()
        status = response.status
        content_type = response.headers.get("Content-Type")
    payload = json.loads(raw.decode("utf-8"))
    data = payload.get("data") or {}
    klines = data.get("klines") or []
    selected = {
        row["trade_date"]: row
        for row in map(parse_kline, klines)
        if row["trade_date"] in TARGET_DATES
    }
    missing = sorted(TARGET_DATES - selected.keys())
    if missing:
        raise RuntimeError(f"missing target dates: {missing}")

    result = {
        "schema_version": "eastmoney_market_probe_v1",
        "evidence_level": "public_secondary_crosscheck",
        "authoritative_exchange_record": False,
        "security_code": "600519.SH",
        "security_name": data.get("name"),
        "currency": "CNY",
        "price_adjustment": "unadjusted",
        "request": {
            "url": request_url,
            "parameters": PARAMS,
            "http_status": status,
            "content_type": content_type,
            "response_sha256": sha256_bytes(raw),
        },
        "target_dates": sorted(TARGET_DATES),
        "rows": [selected[date] for date in sorted(selected)],
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    canonical = json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2)
    OUTPUT.write_text(canonical + "\n", encoding="utf-8")
    print(canonical)


if __name__ == "__main__":
    main()
