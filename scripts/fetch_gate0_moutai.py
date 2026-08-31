#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path
import platform
import time
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request, urlopen


OUTPUT_DIR = Path("data/raw/gate0/moutai/2021-04-01")
USER_AGENT = "value-investing-valuation-system/1.2 (+research; PIT evidence capture)"


@dataclass(slots=True)
class FetchResult:
    name: str
    url: str
    status: str
    file: str | None
    sha256: str | None
    bytes: int | None
    error: str | None


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def fetch_json(url: str, retries: int = 3) -> Any:
    last_error: Exception | None = None
    for attempt in range(retries):
        request = Request(
            url,
            headers={
                "User-Agent": USER_AGENT,
                "Accept": "application/json,text/plain,*/*",
                "Referer": "https://quote.eastmoney.com/",
            },
        )
        try:
            with urlopen(request, timeout=30) as response:
                if response.status != 200:
                    raise RuntimeError(f"HTTP {response.status}")
                raw = response.read()
                return json.loads(raw.decode("utf-8"))
        except Exception as exc:  # noqa: BLE001 - evidence capture records exact failure
            last_error = exc
            time.sleep(2**attempt)
    raise RuntimeError(f"Fetch failed after {retries} attempts: {last_error}")


def write_json(name: str, value: Any) -> tuple[str, str, int]:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUTPUT_DIR / f"{name}.json"
    raw = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True).encode("utf-8")
    path.write_bytes(raw)
    return path.as_posix(), sha256(raw).hexdigest(), len(raw)


def datacenter_url(report_name: str, *, report_date: str | None = None) -> str:
    filters = '(SECURITY_CODE="600519")'
    if report_date is not None:
        filters += f"(REPORT_DATE='{report_date}')"
    params = {
        "reportName": report_name,
        "columns": "ALL",
        "filter": filters,
        "pageNumber": 1,
        "pageSize": 500,
        "sortTypes": -1,
        "sortColumns": "REPORT_DATE",
    }
    return "https://datacenter-web.eastmoney.com/api/data/v1/get?" + urlencode(params)


def market_url() -> str:
    params = {
        "secid": "1.600519",
        "klt": 101,
        "fqt": 0,
        "beg": "20210330",
        "end": "20210402",
        "fields1": "f1,f2,f3,f4,f5,f6",
        "fields2": "f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61",
    }
    return "https://push2his.eastmoney.com/api/qt/stock/kline/get?" + urlencode(params)


def normalize_market(payload: Any) -> list[dict[str, Any]]:
    rows = ((payload or {}).get("data") or {}).get("klines") or []
    output: list[dict[str, Any]] = []
    for raw in rows:
        fields = str(raw).split(",")
        if len(fields) < 7:
            raise ValueError(f"Unexpected kline row: {raw!r}")
        output.append(
            {
                "trade_date": fields[0],
                "open": fields[1],
                "close": fields[2],
                "high": fields[3],
                "low": fields[4],
                "volume": fields[5],
                "turnover": fields[6],
                "currency": "CNY",
                "adjustment": "none",
                "availability_policy": "XSHG close plus 15-minute safety lag",
            }
        )
    return output


def scan_financial_fields(payloads: dict[str, Any]) -> list[dict[str, Any]]:
    keywords = (
        "DEPR",
        "AMORT",
        "CAPEX",
        "CONSTRUCT",
        "PURCHASE",
        "FIXED",
        "INTANG",
        "MONETARY",
        "CASH",
        "LOAN",
        "BORROW",
        "BOND",
        "DEBT",
        "SHARE",
        "CAPITAL",
        "INVENTORY",
        "RECEIV",
        "PAYABLE",
        "WORKING",
    )
    candidates: list[dict[str, Any]] = []
    for dataset, payload in payloads.items():
        rows = (((payload or {}).get("result") or {}).get("data") or [])
        for row_index, row in enumerate(rows):
            if not isinstance(row, dict):
                continue
            for key, value in row.items():
                if any(word in key.upper() for word in keywords):
                    candidates.append(
                        {
                            "dataset": dataset,
                            "row_index": row_index,
                            "source_field": key,
                            "source_value": value,
                        }
                    )
    return sorted(candidates, key=lambda item: (item["dataset"], item["source_field"], item["row_index"]))


def main() -> int:
    retrieved_at = datetime.now(timezone.utc).isoformat()
    resources = {
        "market_window_raw": market_url(),
        "balance_2020_raw": datacenter_url("RPT_DMSK_FN_BALANCE", report_date="2020-12-31"),
        "income_2020_raw": datacenter_url("RPT_DMSK_FN_INCOME", report_date="2020-12-31"),
        "cashflow_2020_raw": datacenter_url("RPT_DMSK_FN_CASHFLOW", report_date="2020-12-31"),
        "dividend_candidate_sharebonus": datacenter_url("RPT_SHAREBONUS_DET"),
        "dividend_candidate_f10": datacenter_url("RPT_F10_DIVIDEND"),
        "dividend_candidate_bonusfinance": datacenter_url("RPT_F10_BONUSFINANCE"),
    }
    results: list[FetchResult] = []
    payloads: dict[str, Any] = {}
    for name, url in resources.items():
        try:
            payload = fetch_json(url)
            payloads[name] = payload
            file_name, digest, byte_count = write_json(name, payload)
            results.append(FetchResult(name, url, "success", file_name, digest, byte_count, None))
        except Exception as exc:  # noqa: BLE001
            results.append(FetchResult(name, url, "failed", None, None, None, str(exc)))

    if "market_window_raw" in payloads:
        normalized = normalize_market(payloads["market_window_raw"])
        file_name, digest, byte_count = write_json("market_window_normalized", normalized)
        results.append(
            FetchResult(
                "market_window_normalized",
                resources["market_window_raw"],
                "success",
                file_name,
                digest,
                byte_count,
                None,
            )
        )

    financial_payloads = {
        name: payload
        for name, payload in payloads.items()
        if name in {"balance_2020_raw", "income_2020_raw", "cashflow_2020_raw"}
    }
    candidates = scan_financial_fields(financial_payloads)
    file_name, digest, byte_count = write_json("financial_field_candidates", candidates)
    results.append(
        FetchResult(
            "financial_field_candidates",
            "derived-from-archived-financial-responses",
            "success",
            file_name,
            digest,
            byte_count,
            None,
        )
    )

    manifest = {
        "retrieved_at": retrieved_at,
        "python": platform.python_version(),
        "user_agent": USER_AGENT,
        "security_code": "600519.SH",
        "decision_at": "2021-04-01T00:00:00+08:00",
        "data_policy": "free/open adapter; derived sources require independent reconciliation",
        "results": [asdict(result) for result in results],
    }
    manifest["manifest_content_hash"] = sha256(canonical_bytes(manifest)).hexdigest()
    write_json("manifest", manifest)

    core = {"market_window_raw", "balance_2020_raw", "income_2020_raw", "cashflow_2020_raw"}
    successful = {result.name for result in results if result.status == "success"}
    return 0 if core <= successful else 1


if __name__ == "__main__":
    raise SystemExit(main())
