from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from hashlib import sha256
import json
from typing import Any, Mapping, Sequence

from .market import CorporateAction


class CorporateActionParseError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class DividendFieldMap:
    cash_amount_fields: tuple[str, ...]
    ex_date_fields: tuple[str, ...]
    record_date_fields: tuple[str, ...] = ()
    payment_date_fields: tuple[str, ...] = ()
    announcement_date_fields: tuple[str, ...] = ()
    cash_unit: str = "per_share"
    currency: str = "CNY"

    def divisor(self) -> Decimal:
        units = {
            "per_share": Decimal("1"),
            "per_10_shares": Decimal("10"),
            "per_100_shares": Decimal("100"),
        }
        try:
            return units[self.cash_unit]
        except KeyError as exc:
            raise CorporateActionParseError(
                f"Unsupported cash dividend unit: {self.cash_unit}"
            ) from exc


def _first_value(payload: Mapping[str, Any], fields: Sequence[str]) -> Any | None:
    for field in fields:
        value = payload.get(field)
        if value not in (None, "", "-"):
            return value
    return None


def _parse_decimal(value: Any, field_group: str) -> Decimal:
    try:
        return Decimal(str(value).replace(",", "").strip())
    except (InvalidOperation, AttributeError) as exc:
        raise CorporateActionParseError(
            f"Invalid numeric value for {field_group}: {value!r}"
        ) from exc


def _parse_date(value: Any, field_group: str, *, required: bool) -> date | None:
    if value in (None, "", "-"):
        if required:
            raise CorporateActionParseError(f"Missing required date: {field_group}")
        return None
    text = str(value).strip()[:10]
    try:
        return date.fromisoformat(text)
    except ValueError as exc:
        raise CorporateActionParseError(
            f"Invalid date for {field_group}: {value!r}"
        ) from exc


def _hash_payload(value: Mapping[str, Any]) -> str:
    canonical = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    return sha256(canonical).hexdigest()


def parse_cash_dividend(
    payload: Mapping[str, Any],
    *,
    security_code: str,
    available_at: datetime,
    field_map: DividendFieldMap,
    source_document_id: str | None = None,
    evidence_grade: int = 1,
) -> CorporateAction:
    """Parse a cash-dividend candidate through an explicit provider field map.

    This function normalizes mechanics only. Evidence quality is carried in
    metadata and must be evaluated separately before formal backtest admission.
    """
    if available_at.tzinfo is None or available_at.utcoffset() is None:
        raise CorporateActionParseError("available_at must be timezone-aware")
    if evidence_grade not in (0, 1, 2, 3):
        raise CorporateActionParseError("evidence_grade must be between 0 and 3")

    raw_amount = _first_value(payload, field_map.cash_amount_fields)
    if raw_amount is None:
        raise CorporateActionParseError("Missing cash dividend amount")
    amount = _parse_decimal(raw_amount, "cash dividend") / field_map.divisor()
    if amount <= 0:
        raise CorporateActionParseError("Cash dividend amount must be positive")

    ex_date = _parse_date(
        _first_value(payload, field_map.ex_date_fields),
        "ex date",
        required=True,
    )
    record_date = _parse_date(
        _first_value(payload, field_map.record_date_fields),
        "record date",
        required=False,
    )
    payment_date = _parse_date(
        _first_value(payload, field_map.payment_date_fields),
        "payment date",
        required=False,
    )
    announcement_date = _parse_date(
        _first_value(payload, field_map.announcement_date_fields),
        "announcement date",
        required=False,
    )
    if payment_date is not None and payment_date < ex_date:
        raise CorporateActionParseError("payment_date cannot be before ex_date")

    announced_at = (
        None
        if announcement_date is None
        else datetime.combine(announcement_date, datetime.min.time(), tzinfo=available_at.tzinfo)
    )
    canonical = {
        "security_code": security_code,
        "action_type": "cash_dividend",
        "available_at": available_at.isoformat(),
        "announced_at": None if announced_at is None else announced_at.isoformat(),
        "ex_date": ex_date.isoformat(),
        "record_date": None if record_date is None else record_date.isoformat(),
        "payment_date": None if payment_date is None else payment_date.isoformat(),
        "cash_amount_per_share": str(amount),
        "currency": field_map.currency,
        "source_document_id": source_document_id,
        "provider_payload_hash": _hash_payload(payload),
        "evidence_grade": evidence_grade,
        "field_map": {
            "cash_amount_fields": field_map.cash_amount_fields,
            "ex_date_fields": field_map.ex_date_fields,
            "record_date_fields": field_map.record_date_fields,
            "payment_date_fields": field_map.payment_date_fields,
            "announcement_date_fields": field_map.announcement_date_fields,
            "cash_unit": field_map.cash_unit,
        },
    }
    return CorporateAction(
        security_code=security_code,
        action_type="cash_dividend",
        available_at=available_at,
        announced_at=announced_at,
        ex_date=ex_date,
        record_date=record_date,
        payment_date=payment_date,
        effective_date=ex_date,
        cash_amount_per_share=amount,
        currency=field_map.currency,
        source_document_id=source_document_id,
        record_hash=_hash_payload(canonical),
    )


def eastmoney_cash_dividend_map() -> DividendFieldMap:
    """Candidate map; formal use still requires official announcement validation."""
    return DividendFieldMap(
        cash_amount_fields=("PRETAX_BONUS_RMB",),
        ex_date_fields=(
            "EX_DIVIDEND_DATE",
            "EX_DATE",
            "EX_RIGHT_DATE",
            "EX_DIVIDEND_DAY",
        ),
        record_date_fields=("EQUITY_RECORD_DATE", "RECORD_DATE"),
        payment_date_fields=(
            "CASH_DIVIDEND_DATE",
            "PAY_CASH_DATE",
            "PAYMENT_DATE",
            "DIVIDEND_DATE",
        ),
        announcement_date_fields=(
            "NOTICE_DATE",
            "ANNOUNCE_DATE",
            "ANNOUNCEMENT_DATE",
        ),
        cash_unit="per_10_shares",
        currency="CNY",
    )
