"""Deterministic, low-turnover total-return backtest components."""

from .costs import CostComponent, calculate_transaction_cost
from .total_return import DailyHoldingPoint, HoldingResult, PriceObservation, simulate_cash_dividend_hold

__all__ = [
    "CostComponent",
    "DailyHoldingPoint",
    "HoldingResult",
    "PriceObservation",
    "calculate_transaction_cost",
    "simulate_cash_dividend_hold",
]
