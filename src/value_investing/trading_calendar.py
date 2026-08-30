"""Versioned exchange-calendar snapshots for historical replay."""
from __future__ import annotations

import hashlib
import json
from bisect import bisect_left, bisect_right
from dataclasses import dataclass
from datetime import date
from typing import Iterable


@dataclass(frozen=True, order=True)
class TradingDay:
    trade_date: date
    is_open: bool
    settlement_date: date | None = None
    source_note: str | None = None

    def validate(self) -> None:
        if self.settlement_date is not None and self.settlement_date < self.trade_date:
            raise ValueError("settlement date cannot precede trade date")


@dataclass(frozen=True)
class CalendarVersion:
    exchange_mic: str
    version: str
    valid_from: date
    valid_to: date | None
    days: tuple[TradingDay, ...]
    source_code: str
    source_document_hash: str
    frozen: bool = False

    def validate(self) -> None:
        if not self.exchange_mic or not self.version or not self.source_code:
            raise ValueError("exchange_mic, version and source_code are required")
        if self.valid_to is not None and self.valid_to < self.valid_from:
            raise ValueError("valid_to cannot precede valid_from")
        if len(self.source_document_hash) != 64:
            raise ValueError("source_document_hash must be SHA-256")
        ordered = sorted(self.days, key=lambda item: item.trade_date)
        if tuple(ordered) != self.days:
            raise ValueError("calendar days must be sorted")
        if len({item.trade_date for item in self.days}) != len(self.days):
            raise ValueError("calendar dates must be unique")
        for item in self.days:
            item.validate()
            if item.trade_date < self.valid_from:
                raise ValueError("calendar day precedes valid_from")
            if self.valid_to is not None and item.trade_date > self.valid_to:
                raise ValueError("calendar day follows valid_to")

    def content_hash(self) -> str:
        self.validate()
        payload = {
            "exchange_mic": self.exchange_mic,
            "version": self.version,
            "valid_from": self.valid_from.isoformat(),
            "valid_to": self.valid_to.isoformat() if self.valid_to else None,
            "source_code": self.source_code,
            "source_document_hash": self.source_document_hash.lower(),
            "days": [
                {
                    "trade_date": item.trade_date.isoformat(),
                    "is_open": item.is_open,
                    "settlement_date": (
                        item.settlement_date.isoformat()
                        if item.settlement_date
                        else None
                    ),
                    "source_note": item.source_note,
                }
                for item in self.days
            ],
        }
        encoded = json.dumps(
            payload,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        return hashlib.sha256(encoded).hexdigest()


class TradingCalendar:
    def __init__(self, version: CalendarVersion):
        version.validate()
        self.version = version
        self._by_date = {item.trade_date: item for item in version.days}
        self._open_dates = tuple(
            item.trade_date for item in version.days if item.is_open
        )

    def is_open(self, day: date) -> bool:
        try:
            return self._by_date[day].is_open
        except KeyError as exc:
            raise ValueError(
                f"date {day} is outside frozen calendar {self.version.version}"
            ) from exc

    def next_open(self, day: date, *, inclusive: bool = False) -> date:
        index = (
            bisect_left(self._open_dates, day)
            if inclusive
            else bisect_right(self._open_dates, day)
        )
        if index >= len(self._open_dates):
            raise ValueError("no later open date exists in frozen calendar")
        return self._open_dates[index]

    def previous_open(self, day: date, *, inclusive: bool = False) -> date:
        index = (
            bisect_right(self._open_dates, day) - 1
            if inclusive
            else bisect_left(self._open_dates, day) - 1
        )
        if index < 0:
            raise ValueError("no earlier open date exists in frozen calendar")
        return self._open_dates[index]

    def settlement_date(self, day: date) -> date:
        try:
            calendar_day = self._by_date[day]
        except KeyError as exc:
            raise ValueError("trade date is outside frozen calendar") from exc
        if not calendar_day.is_open:
            raise ValueError("cannot settle a trade on a closed session")
        if calendar_day.settlement_date is None:
            raise ValueError("settlement date is missing from frozen calendar")
        return calendar_day.settlement_date

    def open_dates(self, start: date, end: date) -> tuple[date, ...]:
        if end < start:
            raise ValueError("end cannot precede start")
        left = bisect_left(self._open_dates, start)
        right = bisect_right(self._open_dates, end)
        return self._open_dates[left:right]


def build_calendar_version(
    *,
    exchange_mic: str,
    version: str,
    valid_from: date,
    valid_to: date | None,
    days: Iterable[TradingDay],
    source_code: str,
    source_document_hash: str,
    frozen: bool = False,
) -> CalendarVersion:
    calendar = CalendarVersion(
        exchange_mic=exchange_mic,
        version=version,
        valid_from=valid_from,
        valid_to=valid_to,
        days=tuple(sorted(days, key=lambda item: item.trade_date)),
        source_code=source_code,
        source_document_hash=source_document_hash,
        frozen=frozen,
    )
    calendar.validate()
    return calendar
