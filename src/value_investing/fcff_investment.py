"""Holding-period investment mathematics for value-driver FCFF models.

The exit value is derived from the *same* forward FCFF path used for today's
valuation. No separate exit multiple is introduced. Equity-bridge balances are
explicit policy inputs because future cash/debt claims are not implied by the
operating DCF itself.
"""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite

from .fcff import ValueDriverFcffAssumptions, ValueDriverFcffResult
from .investment import annualized_return, target_entry_price


@dataclass(frozen=True)
class FcffHoldingResult:
    holding_years: int
    enterprise_value_at_exit: float
    equity_value_at_exit: float
    value_per_share_at_exit: float
    annualized_return: float
    target_entry_price: float


def fcff_enterprise_value_at_horizon(
    result: ValueDriverFcffResult,
    assumptions: ValueDriverFcffAssumptions,
    *,
    holding_years: int = 5,
) -> float:
    """Value all post-horizon FCFF at the end of ``holding_years``.

    The function discounts forecast years ``holding_years + 1 .. N`` and the
    terminal value back to the end of the holding period. Years already owned
    are deliberately excluded; this is an economic exit value, not today's EV.
    """
    if holding_years <= 0:
        raise ValueError("holding_years must be positive")
    if holding_years >= len(result.forecast):
        raise ValueError("holding horizon must be shorter than explicit forecast")
    if assumptions.wacc <= -1 or not isfinite(assumptions.wacc):
        raise ValueError("WACC must be finite and greater than -100%")

    future_fcff = sum(
        year.fcff / ((1.0 + assumptions.wacc) ** (year.year - holding_years))
        for year in result.forecast
        if year.year > holding_years
    )
    terminal = result.terminal_value / (
        (1.0 + assumptions.wacc) ** (len(result.forecast) - holding_years)
    )
    return future_fcff + terminal


def value_fcff_holding_period(
    current_price: float,
    result: ValueDriverFcffResult,
    assumptions: ValueDriverFcffAssumptions,
    *,
    shares_outstanding: float,
    cash_and_investments_at_exit: float,
    debt_at_exit: float,
    minority_interest_at_exit: float = 0.0,
    other_non_operating_assets_at_exit: float = 0.0,
    holding_years: int = 5,
    target_return: float = 0.15,
) -> FcffHoldingResult:
    """Bridge the model-consistent exit EV to an investor return.

    No distributions are assumed during the holding period. If dividends or
    buybacks are material, a security-level cash-flow ledger must be layered on
    top instead of hiding them in this function.
    """
    values = (
        current_price,
        shares_outstanding,
        cash_and_investments_at_exit,
        debt_at_exit,
        minority_interest_at_exit,
        other_non_operating_assets_at_exit,
        target_return,
    )
    if not all(isfinite(value) for value in values):
        raise ValueError("holding-period inputs must be finite")
    if current_price <= 0 or shares_outstanding <= 0:
        raise ValueError("current price and shares must be positive")

    enterprise_value = fcff_enterprise_value_at_horizon(
        result, assumptions, holding_years=holding_years
    )
    equity_value = (
        enterprise_value
        + cash_and_investments_at_exit
        + other_non_operating_assets_at_exit
        - debt_at_exit
        - minority_interest_at_exit
    )
    if equity_value < 0:
        raise ValueError("exit equity value cannot be negative")
    value_per_share = equity_value / shares_outstanding
    return FcffHoldingResult(
        holding_years=holding_years,
        enterprise_value_at_exit=enterprise_value,
        equity_value_at_exit=equity_value,
        value_per_share_at_exit=value_per_share,
        annualized_return=annualized_return(
            current_price, value_per_share, holding_years
        ),
        target_entry_price=target_entry_price(
            value_per_share, target_return, holding_years
        ),
    )
