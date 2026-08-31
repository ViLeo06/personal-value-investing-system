"""Five-year holding-value bridge for value-driver FCFF models.

The operating engine returns an enterprise value at the decision date. This
module re-values the remaining cash flows at a chosen holding horizon, applies
an explicit equity bridge, converts to the security's quote currency, and then
calculates the investor return and target entry price. It does not select
company assumptions or fetch market data.
"""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite

from .fcff import ValueDriverFcffResult


@dataclass(frozen=True)
class ValueDriverHoldingResult:
    horizon_year: int
    operating_value_at_horizon: float
    equity_value_at_horizon: float
    value_per_share_at_horizon: float
    annualized_return: float
    target_buy_price: float


def value_driver_holding_result(
    operating_result: ValueDriverFcffResult,
    *,
    discount_rate: float,
    equity_bridge_value: float,
    shares_outstanding: float,
    current_price: float,
    reporting_to_quote_fx: float = 1.0,
    horizon_year: int = 5,
    target_return: float = 0.15,
) -> ValueDriverHoldingResult:
    """Calculate a deterministic holding-period value and return.

    ``equity_bridge_value`` is expressed in the reporting currency and is
    assumed unchanged at the horizon. This simplification must be disclosed by
    the company-specific model. ``reporting_to_quote_fx`` converts one unit of
    reporting currency into quote currency.
    """

    scalar_values = (
        discount_rate,
        equity_bridge_value,
        shares_outstanding,
        current_price,
        reporting_to_quote_fx,
        target_return,
    )
    if not all(isfinite(value) for value in scalar_values):
        raise ValueError("holding-value inputs must be finite")
    if discount_rate <= -1:
        raise ValueError("discount_rate must be greater than -100%")
    if target_return <= -1:
        raise ValueError("target_return must be greater than -100%")
    if shares_outstanding <= 0:
        raise ValueError("shares_outstanding must be positive")
    if current_price <= 0:
        raise ValueError("current_price must be positive")
    if reporting_to_quote_fx <= 0:
        raise ValueError("reporting_to_quote_fx must be positive")
    if not 1 <= horizon_year < len(operating_result.forecast):
        raise ValueError("horizon_year must fall inside the explicit forecast")

    remaining_fcff_value = sum(
        row.fcff / ((1.0 + discount_rate) ** (row.year - horizon_year))
        for row in operating_result.forecast
        if row.year > horizon_year
    )
    terminal_value_at_horizon = operating_result.terminal_value / (
        (1.0 + discount_rate)
        ** (len(operating_result.forecast) - horizon_year)
    )
    operating_value_at_horizon = remaining_fcff_value + terminal_value_at_horizon
    equity_value_at_horizon = operating_value_at_horizon + equity_bridge_value
    value_per_share_at_horizon = (
        equity_value_at_horizon / shares_outstanding * reporting_to_quote_fx
    )
    if value_per_share_at_horizon <= 0:
        raise ValueError("horizon value per share must be positive")

    annualized_return = (
        value_per_share_at_horizon / current_price
    ) ** (1.0 / horizon_year) - 1.0
    target_buy_price = value_per_share_at_horizon / (
        (1.0 + target_return) ** horizon_year
    )
    return ValueDriverHoldingResult(
        horizon_year=horizon_year,
        operating_value_at_horizon=operating_value_at_horizon,
        equity_value_at_horizon=equity_value_at_horizon,
        value_per_share_at_horizon=value_per_share_at_horizon,
        annualized_return=annualized_return,
        target_buy_price=target_buy_price,
    )
