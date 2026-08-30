"""Convert publication timestamps into earliest tradable availability times."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, time
from typing import Callable
from zoneinfo import ZoneInfo


NextSessionOpen = Callable[[datetime], datetime]


@dataclass(frozen=True)
class ExchangeAvailabilityPolicy:
    exchange_timezone: str
    session_open: time
    session_close: time
    policy_version: str = "exchange_publication_availability_v1"

    def earliest_usable_at(
        self,
        published_at: datetime,
        *,
        next_session_open: NextSessionOpen,
    ) -> datetime:
        if published_at.tzinfo is None:
            raise ValueError("publication timestamp must be timezone-aware")
        zone = ZoneInfo(self.exchange_timezone)
        local = published_at.astimezone(zone)
        open_at = local.replace(
            hour=self.session_open.hour,
            minute=self.session_open.minute,
            second=self.session_open.second,
            microsecond=0,
        )
        close_at = local.replace(
            hour=self.session_close.hour,
            minute=self.session_close.minute,
            second=self.session_close.second,
            microsecond=0,
        )

        if local < open_at:
            return open_at
        if local <= close_at:
            return local
        next_open = next_session_open(local)
        if next_open.tzinfo is None:
            raise ValueError("next-session timestamp must be timezone-aware")
        if next_open <= local:
            raise ValueError("next-session open must be after publication")
        return next_open.astimezone(zone)


SSE_SZSE_AVAILABILITY = ExchangeAvailabilityPolicy(
    exchange_timezone="Asia/Shanghai",
    session_open=time(9, 30),
    session_close=time(15, 0),
)

HKEX_AVAILABILITY = ExchangeAvailabilityPolicy(
    exchange_timezone="Asia/Hong_Kong",
    session_open=time(9, 30),
    session_close=time(16, 0),
)
