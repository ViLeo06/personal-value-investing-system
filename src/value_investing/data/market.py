from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import date, datetime, time
from decimal import Decimal
from hashlib import sha256
import json
from typing import Any, Iterable
from zoneinfo import ZoneInfo


@dataclass(frozen=True, slots=True)
class MarketBar:
    security_code: str
    trade_date: date
    open_price: Decimal
    high_price: Decimal
    low_price: Decimal
    close_price: Decimal
    volume: Decimal | None
    turnover: Decimal | None
    currency: str
    available_at: datetime
    retrieved_at: datetime
    source_code: str
    record_hash: str


@dataclass(frozen=True, slots=True)
class CorporateAction:
    security_code: str
    action_type: str
    available_at: datetime
    announced_at: datetime | None = None
    ex_date: date | None = None
    record_date: date | None = None
    payment_date: date | None = None
    effective_date: date | None = None
    cash_amount_per_share: Decimal | None = None
    currency: str | None = None
    ratio_numerator: Decimal | None = None
    ratio_denominator: Decimal | None = None
    source_document_id: str | None = None
    record_hash: str | None = None


_EXCHANGE_CLOSE = {
    "XSHG": ("Asia/Shanghai", time(15, 15)),
    "XSHE": ("Asia/Shanghai", time(15, 15)),
    "XHKG": ("Asia/Hong_Kong", time(16, 15)),
}


def _decimal(value: Any) -> Decimal:
    return Decimal(str(value))


def _record_hash(payload: dict[str, Any]) -> str:
    raw = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return sha256(raw.encode("utf-8")).hexdigest()


def derived_daily_availability(trade_date: date, exchange_mic: str) -> datetime:
    """Return a conservative historical availability timestamp for a daily bar."""
    try:
        zone_name, close_time = _EXCHANGE_CLOSE[exchange_mic]
    except KeyError as exc:
        raise ValueError(f"Unsupported exchange MIC: {exchange_mic}") from exc
    return datetime.combine(trade_date, close_time, tzinfo=ZoneInfo(zone_name))


def parse_eastmoney_kline_payload(
    payload: dict[str, Any],
    *,
    security_code: str,
    exchange_mic: str,
    currency: str,
    retrieved_at: datetime,
    source_code: str = "AKSHARE_EASTMONEY_DERIVED",
) -> list[MarketBar]:
    """Normalize Eastmoney-style kline rows without coupling the domain to HTTP.

    Expected row order: date, open, close, high, low, volume, turnover, ...
    Raw provider payloads must be archived separately before this transformer runs.
    """
    if retrieved_at.tzinfo is None or retrieved_at.utcoffset() is None:
        raise ValueError("retrieved_at must be timezone-aware")
    data = payload.get("data") or {}
    raw_rows = data.get("klines") or []
    result: list[MarketBar] = []
    for raw in raw_rows:
        parts = raw.split(",") if isinstance(raw, str) else list(raw)
        if len(parts) < 7:
            raise ValueError(f"Kline row has too few fields: {raw!r}")
        row_date = date.fromisoformat(str(parts[0]))
        open_price = _decimal(parts[1])
        close_price = _decimal(parts[2])
        high_price = _decimal(parts[3])
        low_price = _decimal(parts[4])
        volume = None if parts[5] in (None, "", "-") else _decimal(parts[5])
        turnover = None if parts[6] in (None, "", "-") else _decimal(parts[6])
        if min(open_price, high_price, low_price, close_price) < 0:
            raise ValueError("Price fields cannot be negative")
        if high_price < max(open_price, close_price, low_price):
            raise ValueError("High price is inconsistent with OHLC")
        if low_price > min(open_price, close_price, high_price):
            raise ValueError("Low price is inconsistent with OHLC")
        canonical = {
            "security_code": security_code,
            "trade_date": row_date.isoformat(),
            "open": str(open_price),
            "high": str(high_price),
            "low": str(low_price),
            "close": str(close_price),
            "volume": None if volume is None else str(volume),
            "turnover": None if turnover is None else str(turnover),
            "currency": currency,
            "source_code": source_code,
        }
        result.append(
            MarketBar(
                security_code=security_code,
                trade_date=row_date,
                open_price=open_price,
                high_price=high_price,
                low_price=low_price,
                close_price=close_price,
                volume=volume,
                turnover=turnover,
                currency=currency,
                available_at=derived_daily_availability(row_date, exchange_mic),
                retrieved_at=retrieved_at,
                source_code=source_code,
                record_hash=_record_hash(canonical),
            )
        )
    return sorted(result, key=lambda row: row.trade_date)


def normalize_cash_dividend(
    *,
    security_code: str,
    available_at: datetime,
    announced_at: datetime | None,
    ex_date: date,
    record_date: date | None,
    payment_date: date | None,
    cash_amount_per_share: Decimal,
    currency: str,
    source_document_id: str | None,
) -> CorporateAction:
    if available_at.tzinfo is None or available_at.utcoffset() is None:
        raise ValueError("available_at must be timezone-aware")
    if cash_amount_per_share < 0:
        raise ValueError("Cash dividend cannot be negative")
    canonical = {
        "security_code": security_code,
        "action_type": "cash_dividend",
        "available_at": available_at.isoformat(),
        "announced_at": None if announced_at is None else announced_at.isoformat(),
        "ex_date": ex_date.isoformat(),
        "record_date": None if record_date is None else record_date.isoformat(),
        "payment_date": None if payment_date is None else payment_date.isoformat(),
        "cash_amount_per_share": str(cash_amount_per_share),
        "currency": currency,
        "source_document_id": source_document_id,
    }
    return CorporateAction(
        security_code=security_code,
        action_type="cash_dividend",
        available_at=available_at,
        announced_at=announced_at,
        ex_date=ex_date,
        record_date=record_date,
        payment_date=payment_date,
        cash_amount_per_share=cash_amount_per_share,
        currency=currency,
        source_document_id=source_document_id,
        record_hash=_record_hash(canonical),
    )


def rows_as_dicts(rows: Iterable[MarketBar]) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    for row in rows:
        item = asdict(row)
        for key, value in list(item.items()):
            if isinstance(value, Decimal):
                item[key] = str(value)
            elif isinstance(value, (date, datetime)):
                item[key] = value.isoformat()
        output.append(item)
    return output
