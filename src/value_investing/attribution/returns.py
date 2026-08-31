from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class ReturnAttribution:
    opening_value: float
    price_effect: float
    fx_effect: float
    price_fx_interaction: float
    dividends: float
    fees: float
    closing_value: float

    @property
    def explained_change(self) -> float:
        return (
            self.price_effect
            + self.fx_effect
            + self.price_fx_interaction
            + self.dividends
            - self.fees
        )

    @property
    def residual(self) -> float:
        return self.closing_value - self.opening_value - self.explained_change


def attribute_equity_return(
    *,
    quantity: float,
    opening_price_local: float,
    closing_price_local: float,
    opening_fx_to_base: float,
    closing_fx_to_base: float,
    dividends_base: float = 0.0,
    fees_base: float = 0.0,
) -> ReturnAttribution:
    """Attribute local-price and FX changes in the investor base currency."""
    if quantity < 0:
        raise ValueError("quantity cannot be negative")
    if min(
        opening_price_local,
        closing_price_local,
        opening_fx_to_base,
        closing_fx_to_base,
    ) < 0:
        raise ValueError("prices and FX rates cannot be negative")
    if dividends_base < 0 or fees_base < 0:
        raise ValueError("dividends and fees cannot be negative")

    opening_value = quantity * opening_price_local * opening_fx_to_base
    closing_security_value = quantity * closing_price_local * closing_fx_to_base
    price_effect = quantity * (closing_price_local - opening_price_local) * opening_fx_to_base
    fx_effect = quantity * opening_price_local * (closing_fx_to_base - opening_fx_to_base)
    price_fx_interaction = (
        quantity
        * (closing_price_local - opening_price_local)
        * (closing_fx_to_base - opening_fx_to_base)
    )
    closing_value = closing_security_value + dividends_base - fees_base
    return ReturnAttribution(
        opening_value=opening_value,
        price_effect=price_effect,
        fx_effect=fx_effect,
        price_fx_interaction=price_fx_interaction,
        dividends=dividends_base,
        fees=fees_base,
        closing_value=closing_value,
    )
