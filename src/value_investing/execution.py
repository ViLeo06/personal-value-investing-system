"""Deterministic order rounding, execution costs and position updates."""
from __future__ import annotations

from dataclasses import dataclass
from math import floor, isfinite


@dataclass(frozen=True)
class TradingTerms:
    board_lot: float = 1.0
    minimum_price_increment: float | None = None


@dataclass(frozen=True)
class CostSchedule:
    buy_commission_rate: float = 0.0
    sell_commission_rate: float = 0.0
    minimum_commission: float = 0.0
    buy_tax_rate: float = 0.0
    sell_tax_rate: float = 0.0
    transfer_fee_rate: float = 0.0


@dataclass(frozen=True)
class ExecutionCosts:
    commission: float
    tax: float
    transfer_fee: float

    @property
    def total(self) -> float:
        return self.commission + self.tax + self.transfer_fee


@dataclass(frozen=True)
class PositionState:
    cash: float
    quantity: float


@dataclass(frozen=True)
class ExecutedTrade:
    side: str
    quantity: float
    price: float
    gross_value: float
    costs: ExecutionCosts
    resulting_state: PositionState


def _require_finite(*values: float) -> None:
    if not all(isfinite(value) for value in values):
        raise ValueError("execution inputs must be finite")


def round_price(price: float, terms: TradingTerms) -> float:
    _require_finite(price, terms.board_lot)
    if price < 0:
        raise ValueError("price cannot be negative")
    tick = terms.minimum_price_increment
    if tick is None:
        return price
    if not isfinite(tick) or tick <= 0:
        raise ValueError("price increment must be finite and positive")
    return round(price / tick) * tick


def round_buy_quantity(requested_quantity: float, terms: TradingTerms) -> float:
    _require_finite(requested_quantity, terms.board_lot)
    if requested_quantity < 0:
        raise ValueError("requested quantity cannot be negative")
    if terms.board_lot <= 0:
        raise ValueError("board lot must be positive")
    return floor((requested_quantity + 1e-12) / terms.board_lot) * terms.board_lot


def estimate_execution_costs(
    side: str,
    quantity: float,
    price: float,
    schedule: CostSchedule,
) -> ExecutionCosts:
    if side not in {"buy", "sell"}:
        raise ValueError("side must be buy or sell")
    values = (
        quantity,
        price,
        schedule.buy_commission_rate,
        schedule.sell_commission_rate,
        schedule.minimum_commission,
        schedule.buy_tax_rate,
        schedule.sell_tax_rate,
        schedule.transfer_fee_rate,
    )
    _require_finite(*values)
    if quantity < 0 or price < 0:
        raise ValueError("quantity and price cannot be negative")
    if any(value < 0 for value in values[2:]):
        raise ValueError("cost rates and minimum commission cannot be negative")
    gross = quantity * price
    commission_rate = (
        schedule.buy_commission_rate if side == "buy" else schedule.sell_commission_rate
    )
    tax_rate = schedule.buy_tax_rate if side == "buy" else schedule.sell_tax_rate
    commission = 0.0 if gross == 0 else max(gross * commission_rate, schedule.minimum_commission)
    return ExecutionCosts(
        commission=commission,
        tax=gross * tax_rate,
        transfer_fee=gross * schedule.transfer_fee_rate,
    )


def execute_trade(
    state: PositionState,
    *,
    side: str,
    requested_quantity: float,
    price: float,
    terms: TradingTerms,
    schedule: CostSchedule,
    allow_odd_lot_sell: bool = True,
) -> ExecutedTrade:
    _require_finite(state.cash, state.quantity, requested_quantity, price)
    if state.cash < 0 or state.quantity < 0:
        raise ValueError("cash and quantity cannot be negative")
    if side not in {"buy", "sell"}:
        raise ValueError("side must be buy or sell")
    execution_price = round_price(price, terms)
    quantity = (
        round_buy_quantity(requested_quantity, terms)
        if side == "buy" or not allow_odd_lot_sell
        else requested_quantity
    )
    if quantity < 0:
        raise ValueError("executed quantity cannot be negative")
    if side == "sell" and quantity > state.quantity + 1e-12:
        raise ValueError("cannot sell more than the current position")

    costs = estimate_execution_costs(side, quantity, execution_price, schedule)
    gross = quantity * execution_price
    if side == "buy":
        cash_required = gross + costs.total
        if cash_required > state.cash + 1e-10:
            raise ValueError("insufficient cash for purchase and costs")
        resulting_state = PositionState(
            cash=state.cash - cash_required,
            quantity=state.quantity + quantity,
        )
    else:
        resulting_state = PositionState(
            cash=state.cash + gross - costs.total,
            quantity=state.quantity - quantity,
        )
    return ExecutedTrade(
        side=side,
        quantity=quantity,
        price=execution_price,
        gross_value=gross,
        costs=costs,
        resulting_state=resulting_state,
    )


def affordable_buy_quantity(
    cash: float,
    price: float,
    terms: TradingTerms,
    schedule: CostSchedule,
) -> float:
    _require_finite(cash, price)
    if cash < 0 or price <= 0:
        raise ValueError("cash must be non-negative and price positive")
    initial = round_buy_quantity(cash / price, terms)
    quantity = initial
    while quantity > 0:
        costs = estimate_execution_costs("buy", quantity, round_price(price, terms), schedule)
        if quantity * round_price(price, terms) + costs.total <= cash + 1e-10:
            return quantity
        quantity -= terms.board_lot
    return 0.0
