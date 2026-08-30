"""Corporate-action-aware total-return reconstruction."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from math import isfinite
from typing import Iterable


@dataclass(frozen=True)
class CorporateAction:
    event_date: date
    action_type: str
    cash_amount_per_share: float = 0.0
    reinvestment_price: float | None = None
    share_multiplier: float = 1.0
    currency: str | None = None
    note: str | None = None

    def validate(self) -> None:
        if not isfinite(self.cash_amount_per_share) or self.cash_amount_per_share < 0:
            raise ValueError("cash amount must be finite and non-negative")
        if self.reinvestment_price is not None and (
            not isfinite(self.reinvestment_price) or self.reinvestment_price <= 0
        ):
            raise ValueError("reinvestment price must be finite and positive")
        if not isfinite(self.share_multiplier) or self.share_multiplier <= 0:
            raise ValueError("share multiplier must be finite and positive")
        if self.cash_amount_per_share > 0 and self.reinvestment_price is None:
            raise ValueError("cash/equivalent distributions require a reinvestment price")


@dataclass(frozen=True)
class LedgerEntry:
    event: CorporateAction
    shares_before: float
    shares_after_reinvestment: float
    shares_after_action: float


@dataclass(frozen=True)
class TotalReturnResult:
    start_price: float
    end_price: float
    initial_shares: float
    final_shares: float
    terminal_value: float
    total_return: float
    annualized_return: float
    entries: tuple[LedgerEntry, ...]


def reconstruct_total_return(
    *,
    start_price: float,
    end_price: float,
    actions: Iterable[CorporateAction],
    years: float,
    initial_shares: float = 1.0,
) -> TotalReturnResult:
    if start_price <= 0 or end_price < 0:
        raise ValueError("prices must be valid and start price must be positive")
    if years <= 0:
        raise ValueError("years must be positive")
    if initial_shares <= 0:
        raise ValueError("initial shares must be positive")

    shares = initial_shares
    entries: list[LedgerEntry] = []
    last_date: date | None = None
    for action in sorted(actions, key=lambda item: item.event_date):
        action.validate()
        if last_date is not None and action.event_date < last_date:
            raise ValueError("corporate actions must be chronologically sortable")
        before = shares
        after_reinvestment = shares
        if action.cash_amount_per_share > 0:
            assert action.reinvestment_price is not None
            after_reinvestment = shares * (
                1.0 + action.cash_amount_per_share / action.reinvestment_price
            )
        shares = after_reinvestment * action.share_multiplier
        entries.append(
            LedgerEntry(
                event=action,
                shares_before=before,
                shares_after_reinvestment=after_reinvestment,
                shares_after_action=shares,
            )
        )
        last_date = action.event_date

    terminal_value = shares * end_price
    total_return = terminal_value / (initial_shares * start_price) - 1.0
    annualized_return = (1.0 + total_return) ** (1.0 / years) - 1.0
    return TotalReturnResult(
        start_price=start_price,
        end_price=end_price,
        initial_shares=initial_shares,
        final_shares=shares,
        terminal_value=terminal_value,
        total_return=total_return,
        annualized_return=annualized_return,
        entries=tuple(entries),
    )
