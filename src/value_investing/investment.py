"""Shared investment-return mathematics independent of valuation family."""
from __future__ import annotations

from math import isfinite


def annualized_return(start_value: float, end_value: float, years: float) -> float:
    if not all(isfinite(value) for value in (start_value, end_value, years)):
        raise ValueError("return inputs must be finite")
    if start_value <= 0 or end_value < 0:
        raise ValueError("start value must be positive and end value non-negative")
    if years <= 0:
        raise ValueError("years must be positive")
    if end_value == 0:
        return -1.0
    return (end_value / start_value) ** (1.0 / years) - 1.0


def target_entry_price(end_value: float, hurdle: float, years: float) -> float:
    if not all(isfinite(value) for value in (end_value, hurdle, years)):
        raise ValueError("target-price inputs must be finite")
    if end_value < 0:
        raise ValueError("end value must be non-negative")
    if hurdle <= -1:
        raise ValueError("hurdle must be greater than -100%")
    if years <= 0:
        raise ValueError("years must be positive")
    return end_value / ((1.0 + hurdle) ** years)


def margin_of_safety(price: float, intrinsic_value: float) -> float:
    if not all(isfinite(value) for value in (price, intrinsic_value)):
        raise ValueError("margin-of-safety inputs must be finite")
    if price < 0 or intrinsic_value <= 0:
        raise ValueError("price must be non-negative and intrinsic value positive")
    return 1.0 - price / intrinsic_value
