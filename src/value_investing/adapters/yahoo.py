"""Yahoo chart adapter for provisional prices and corporate-action discovery.

The adapter is intentionally marked as a derived source. It is useful for
building and testing a complete total-return ledger, but official exchange,
issuer or fund disclosures remain the authority for a formal run.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, time, timezone
from hashlib import md5
import json
from math import isfinite
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo


ADAPTER_VERSION = "yahoo_chart_v1"
ENDPOINT = "https://query1.finance.yahoo.com/v8/finance/chart"
SHANGHAI = ZoneInfo("Asia/Shanghai")


@dataclass(frozen=True, slots=True)
class YahooDailyBar:
    provider_symbol: str
    trade_date: date
    open_price: float | None
    high_price: float | None
    low_price: float | None
    close_price: float
    adjusted_close: float | None
    previous_close: float | None
    volume: float | None
    available_at: datetime
    record_hash: str


@dataclass(frozen=True, slots=True)
class YahooDividend:
    provider_event_key: str
    ex_date: date
    amount_per_share: float
    currency: str
    record_hash: str
    raw_event: dict[str, Any]


@dataclass(frozen=True, slots=True)
class YahooSplit:
    provider_event_key: str
    effective_date: date
    numerator: float
    denominator: float
    record_hash: str
    raw_event: dict[str, Any]


@dataclass(frozen=True, slots=True)
class YahooChartResult:
    provider_symbol: str
    currency: str
    exchange_timezone: str
    bars: tuple[YahooDailyBar, ...]
    dividends: tuple[YahooDividend, ...]
    splits: tuple[YahooSplit, ...]
    metadata: dict[str, Any]


def build_chart_url(provider_symbol: str, begin: date, end_exclusive: date) -> str:
    if not provider_symbol.strip():
        raise ValueError("provider_symbol is required")
    if begin >= end_exclusive:
        raise ValueError("begin must precede end_exclusive")
    period1 = int(datetime.combine(begin, time.min, SHANGHAI).timestamp())
    period2 = int(datetime.combine(end_exclusive, time.min, SHANGHAI).timestamp())
    query = urlencode(
        {
            "period1": period1,
            "period2": period2,
            "interval": "1d",
            "events": "div,splits",
            "includeAdjustedClose": "true",
        }
    )
    return f"{ENDPOINT}/{provider_symbol}?{query}"


def _optional_float(value: Any) -> float | None:
    if value is None:
        return None
    result = float(value)
    if not isfinite(result):
        raise ValueError("non-finite numeric value in provider payload")
    return result


def _event_date(epoch: Any, timezone_name: str) -> date:
    return datetime.fromtimestamp(int(epoch), ZoneInfo(timezone_name)).date()


def _hash(parts: list[str]) -> str:
    return md5("|".join(parts).encode("utf-8"), usedforsecurity=False).hexdigest()


def parse_chart_payload(payload: dict[str, Any], provider_symbol: str) -> YahooChartResult:
    chart = payload.get("chart")
    if not isinstance(chart, dict):
        raise ValueError("response does not contain chart")
    if chart.get("error") is not None:
        raise RuntimeError(f"provider error: {chart['error']}")
    results = chart.get("result")
    if not isinstance(results, list) or not results:
        raise ValueError("response does not contain a chart result")
    root = results[0]
    if not isinstance(root, dict):
        raise ValueError("chart result must be an object")

    metadata = root.get("meta") or {}
    timezone_name = metadata.get("exchangeTimezoneName") or "Asia/Shanghai"
    currency = metadata.get("currency") or "CNY"
    timestamps = root.get("timestamp") or []
    indicators = root.get("indicators") or {}
    quotes = (indicators.get("quote") or [{}])[0]
    adjusted = (indicators.get("adjclose") or [{}])[0].get("adjclose") or []

    def series(name: str) -> list[Any]:
        values = quotes.get(name) or []
        return list(values)

    opens, highs, lows = series("open"), series("high"), series("low")
    closes, volumes = series("close"), series("volume")
    bars: list[YahooDailyBar] = []
    previous_close: float | None = None
    for index, epoch in enumerate(timestamps):
        close = _optional_float(closes[index] if index < len(closes) else None)
        if close is None:
            continue
        trade_date = _event_date(epoch, timezone_name)
        raw_fields = [
            provider_symbol,
            trade_date.isoformat(),
            str(opens[index] if index < len(opens) else None),
            str(highs[index] if index < len(highs) else None),
            str(lows[index] if index < len(lows) else None),
            str(close),
            str(volumes[index] if index < len(volumes) else None),
            "YAHOO_CHART_API",
            "unadjusted",
        ]
        bars.append(
            YahooDailyBar(
                provider_symbol=provider_symbol,
                trade_date=trade_date,
                open_price=_optional_float(opens[index] if index < len(opens) else None),
                high_price=_optional_float(highs[index] if index < len(highs) else None),
                low_price=_optional_float(lows[index] if index < len(lows) else None),
                close_price=close,
                adjusted_close=_optional_float(adjusted[index] if index < len(adjusted) else None),
                previous_close=previous_close,
                volume=_optional_float(volumes[index] if index < len(volumes) else None),
                available_at=datetime.combine(trade_date, time(15, 0), ZoneInfo(timezone_name)),
                record_hash=_hash(raw_fields),
            )
        )
        previous_close = close

    events = root.get("events") or {}
    dividends: list[YahooDividend] = []
    for key, event in sorted((events.get("dividends") or {}).items()):
        ex_date = _event_date(event["date"], timezone_name)
        amount = float(event["amount"])
        if not isfinite(amount) or amount < 0:
            raise ValueError("invalid dividend amount")
        dividends.append(
            YahooDividend(
                provider_event_key=str(key),
                ex_date=ex_date,
                amount_per_share=amount,
                currency=currency,
                record_hash=_hash(
                    [provider_symbol, "cash_dividend", ex_date.isoformat(), str(amount), str(key)]
                ),
                raw_event=dict(event),
            )
        )

    splits: list[YahooSplit] = []
    for key, event in sorted((events.get("splits") or {}).items()):
        effective_date = _event_date(event["date"], timezone_name)
        numerator = float(event.get("numerator"))
        denominator = float(event.get("denominator"))
        if numerator <= 0 or denominator <= 0:
            raise ValueError("invalid split ratio")
        splits.append(
            YahooSplit(
                provider_event_key=str(key),
                effective_date=effective_date,
                numerator=numerator,
                denominator=denominator,
                record_hash=_hash(
                    [provider_symbol, "split", effective_date.isoformat(), str(numerator), str(denominator), str(key)]
                ),
                raw_event=dict(event),
            )
        )

    return YahooChartResult(
        provider_symbol=provider_symbol,
        currency=currency,
        exchange_timezone=timezone_name,
        bars=tuple(bars),
        dividends=tuple(dividends),
        splits=tuple(splits),
        metadata=dict(metadata),
    )


def fetch_chart(
    provider_symbol: str,
    begin: date,
    end_exclusive: date,
    *,
    timeout_seconds: float = 30.0,
) -> tuple[YahooChartResult, bytes]:
    """Return normalized result and exact raw bytes for evidence archival."""

    url = build_chart_url(provider_symbol, begin, end_exclusive)
    request = Request(url, headers={"User-Agent": "value-investing-valuation-system/0.1"})
    with urlopen(request, timeout=timeout_seconds) as response:  # noqa: S310 - fixed HTTPS host
        if response.status != 200:
            raise RuntimeError(f"chart request failed with HTTP {response.status}")
        raw = response.read()
    payload = json.loads(raw.decode("utf-8"))
    return parse_chart_payload(payload, provider_symbol), raw
