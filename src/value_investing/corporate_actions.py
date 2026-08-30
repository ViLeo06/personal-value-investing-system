"""Deterministic shareholder ledger for corporate actions and total return."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from math import isfinite
from typing import Sequence


@dataclass(frozen=True)
class ShareholderState:
    quantity: float
    cash: float = 0.0


@dataclass(frozen=True)
class CorporateActionEvent:
    action_id: str
    action_type: str
    effective_date: date
    available_at: datetime
    cash_amount_per_share: float | None = None
    ratio_numerator: float | None = None
    ratio_denominator: float | None = None
    subscription_price: float | None = None
    currency: str | None = None


@dataclass(frozen=True)
class ReinvestmentInstruction:
    action_id: str
    price: float
    participation_rate: float = 1.0
    withholding_tax_rate: float = 0.0


@dataclass(frozen=True)
class CorporateActionLedgerEntry:
    action_id: str
    action_type: str
    effective_date: date
    opening_quantity: float
    opening_cash: float
    quantity_change: float
    cash_change: float
    closing_quantity: float
    closing_cash: float
    reinvestment_price: float | None


@dataclass(frozen=True)
class CorporateActionLedgerResult:
    final_state: ShareholderState
    entries: tuple[CorporateActionLedgerEntry, ...]


def _ratio(event: CorporateActionEvent) -> float:
    numerator = event.ratio_numerator
    denominator = event.ratio_denominator
    if numerator is None or denominator is None:
        raise ValueError(f"ratio is required for {event.action_id}")
    if not all(isfinite(value) for value in (numerator, denominator)):
        raise ValueError("corporate-action ratios must be finite")
    if numerator < 0 or denominator <= 0:
        raise ValueError("ratio numerator must be non-negative and denominator positive")
    return numerator / denominator


def apply_corporate_actions(
    initial_state: ShareholderState,
    events: Sequence[CorporateActionEvent],
    *,
    decision_at: datetime,
    reinvestments: Sequence[ReinvestmentInstruction] = (),
    allow_fractional_shares: bool = True,
) -> CorporateActionLedgerResult:
    if decision_at.tzinfo is None:
        raise ValueError("decision timestamp must be timezone-aware")
    if initial_state.quantity < 0 or initial_state.cash < 0:
        raise ValueError("initial shares and cash cannot be negative")
    if not all(isfinite(value) for value in (initial_state.quantity, initial_state.cash)):
        raise ValueError("initial state must be finite")

    reinvestment_map = {instruction.action_id: instruction for instruction in reinvestments}
    if len(reinvestment_map) != len(reinvestments):
        raise ValueError("reinvestment instructions must have unique action IDs")
    for instruction in reinvestments:
        if not isfinite(instruction.price) or instruction.price <= 0:
            raise ValueError("reinvestment price must be finite and positive")
        if not 0 <= instruction.participation_rate <= 1:
            raise ValueError("participation rate must be in [0, 1]")
        if not 0 <= instruction.withholding_tax_rate < 1:
            raise ValueError("withholding tax rate must be in [0, 1)")

    ordered = sorted(events, key=lambda event: (event.effective_date, event.action_id))
    if len({event.action_id for event in ordered}) != len(ordered):
        raise ValueError("corporate action IDs must be unique")

    state = initial_state
    entries: list[CorporateActionLedgerEntry] = []
    for event in ordered:
        if event.available_at.tzinfo is None:
            raise ValueError("action availability timestamps must be timezone-aware")
        if event.available_at > decision_at and event.effective_date <= decision_at.date():
            raise ValueError(
                f"PIT leakage: {event.action_id} was not known by the decision timestamp"
            )
        opening = state
        quantity_change = 0.0
        cash_change = 0.0
        reinvestment_price: float | None = None

        if event.action_type == "cash_dividend":
            if event.cash_amount_per_share is None or not isfinite(event.cash_amount_per_share):
                raise ValueError("cash dividend amount must be finite")
            if event.cash_amount_per_share < 0:
                raise ValueError("cash dividend cannot be negative")
            instruction = reinvestment_map.get(event.action_id)
            tax_rate = instruction.withholding_tax_rate if instruction else 0.0
            gross_cash = opening.quantity * event.cash_amount_per_share
            net_cash = gross_cash * (1.0 - tax_rate)
            cash_change = net_cash
            state = ShareholderState(opening.quantity, opening.cash + net_cash)
            if instruction and instruction.participation_rate > 0:
                reinvestment_price = instruction.price
                cash_to_reinvest = net_cash * instruction.participation_rate
                shares_bought = cash_to_reinvest / instruction.price
                if not allow_fractional_shares:
                    shares_bought = float(int(shares_bought))
                quantity_change += shares_bought
                cash_change -= shares_bought * instruction.price
                state = ShareholderState(
                    state.quantity + shares_bought,
                    state.cash - shares_bought * instruction.price,
                )
        elif event.action_type in {"stock_dividend", "split"}:
            multiplier = 1.0 + _ratio(event) if event.action_type == "stock_dividend" else _ratio(event)
            new_quantity = opening.quantity * multiplier
            quantity_change = new_quantity - opening.quantity
            state = ShareholderState(new_quantity, opening.cash)
        elif event.action_type == "reverse_split":
            multiplier = _ratio(event)
            if multiplier > 1:
                raise ValueError("reverse-split multiplier must not exceed one")
            new_quantity = opening.quantity * multiplier
            quantity_change = new_quantity - opening.quantity
            state = ShareholderState(new_quantity, opening.cash)
        elif event.action_type == "rights_issue":
            rights_ratio = _ratio(event)
            if event.subscription_price is None or not isfinite(event.subscription_price):
                raise ValueError("rights subscription price must be finite")
            if event.subscription_price < 0:
                raise ValueError("rights subscription price cannot be negative")
            instruction = reinvestment_map.get(event.action_id)
            participation = instruction.participation_rate if instruction else 0.0
            subscribed = opening.quantity * rights_ratio * participation
            cash_required = subscribed * event.subscription_price
            if cash_required > opening.cash + 1e-10:
                raise ValueError("insufficient cash to exercise rights")
            quantity_change = subscribed
            cash_change = -cash_required
            state = ShareholderState(
                opening.quantity + subscribed,
                opening.cash - cash_required,
            )
        else:
            raise ValueError(f"unsupported corporate action type: {event.action_type}")

        entries.append(
            CorporateActionLedgerEntry(
                action_id=event.action_id,
                action_type=event.action_type,
                effective_date=event.effective_date,
                opening_quantity=opening.quantity,
                opening_cash=opening.cash,
                quantity_change=quantity_change,
                cash_change=cash_change,
                closing_quantity=state.quantity,
                closing_cash=state.cash,
                reinvestment_price=reinvestment_price,
            )
        )
    return CorporateActionLedgerResult(state, tuple(entries))


def terminal_shareholder_value(state: ShareholderState, closing_price: float) -> float:
    if not isfinite(closing_price) or closing_price < 0:
        raise ValueError("closing price must be finite and non-negative")
    return state.quantity * closing_price + state.cash
