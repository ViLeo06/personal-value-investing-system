"""Residual-income valuation primitives for banks and other financial firms."""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite
from typing import Sequence

from .valuation import bounded_bisection, present_value, SolveResult


@dataclass(frozen=True)
class ResidualIncomeYear:
    year: int
    opening_book_value_per_share: float
    roe: float
    earnings_per_share: float
    payout_ratio: float
    dividend_per_share: float
    closing_book_value_per_share: float
    residual_income_per_share: float
    present_value: float


@dataclass(frozen=True)
class ResidualIncomeAssumptions:
    opening_book_value_per_share: float
    roe_path: Sequence[float]
    payout_ratio_path: Sequence[float]
    cost_of_equity: float
    terminal_roe: float
    terminal_growth: float


@dataclass(frozen=True)
class ResidualIncomeResult:
    intrinsic_value_per_share: float
    opening_book_value_per_share: float
    pv_explicit_residual_income: float
    pv_terminal_residual_income: float
    terminal_residual_income_value: float
    terminal_value_share: float
    forecast: tuple[ResidualIncomeYear, ...]


def _validate(assumptions: ResidualIncomeAssumptions) -> None:
    if not assumptions.roe_path or len(assumptions.roe_path) != len(assumptions.payout_ratio_path):
        raise ValueError("ROE and payout paths must have one equal non-zero length")
    values = (
        assumptions.opening_book_value_per_share,
        assumptions.cost_of_equity,
        assumptions.terminal_roe,
        assumptions.terminal_growth,
        *assumptions.roe_path,
        *assumptions.payout_ratio_path,
    )
    if not all(isfinite(value) for value in values):
        raise ValueError("all assumptions must be finite")
    if assumptions.opening_book_value_per_share <= 0:
        raise ValueError("opening book value must be positive")
    if assumptions.cost_of_equity <= assumptions.terminal_growth:
        raise ValueError("cost of equity must exceed terminal growth")
    if assumptions.terminal_growth < 0:
        raise ValueError("terminal growth must be non-negative")
    if any(not 0 <= payout <= 1 for payout in assumptions.payout_ratio_path):
        raise ValueError("payout ratios must be in [0, 1]")


def value_residual_income(assumptions: ResidualIncomeAssumptions) -> ResidualIncomeResult:
    """Value equity as opening book value plus discounted residual income."""
    _validate(assumptions)
    book_value = assumptions.opening_book_value_per_share
    forecast: list[ResidualIncomeYear] = []
    pv_explicit = 0.0

    for year, (roe, payout) in enumerate(
        zip(assumptions.roe_path, assumptions.payout_ratio_path, strict=True),
        start=1,
    ):
        earnings = book_value * roe
        dividend = earnings * payout
        closing_book = book_value + earnings - dividend
        residual_income = book_value * (roe - assumptions.cost_of_equity)
        pv = present_value(residual_income, assumptions.cost_of_equity, year)
        forecast.append(
            ResidualIncomeYear(
                year=year,
                opening_book_value_per_share=book_value,
                roe=roe,
                earnings_per_share=earnings,
                payout_ratio=payout,
                dividend_per_share=dividend,
                closing_book_value_per_share=closing_book,
                residual_income_per_share=residual_income,
                present_value=pv,
            )
        )
        pv_explicit += pv
        book_value = closing_book

    next_residual_income = book_value * (
        assumptions.terminal_roe - assumptions.cost_of_equity
    )
    terminal_value = next_residual_income / (
        assumptions.cost_of_equity - assumptions.terminal_growth
    )
    pv_terminal = present_value(
        terminal_value, assumptions.cost_of_equity, len(forecast)
    )
    intrinsic_value = (
        assumptions.opening_book_value_per_share + pv_explicit + pv_terminal
    )
    terminal_share = pv_terminal / intrinsic_value if intrinsic_value != 0 else 0.0
    return ResidualIncomeResult(
        intrinsic_value_per_share=intrinsic_value,
        opening_book_value_per_share=assumptions.opening_book_value_per_share,
        pv_explicit_residual_income=pv_explicit,
        pv_terminal_residual_income=pv_terminal,
        terminal_residual_income_value=terminal_value,
        terminal_value_share=terminal_share,
        forecast=tuple(forecast),
    )


def implied_uniform_roe(
    target_price: float,
    template: ResidualIncomeAssumptions,
    *,
    lower: float = -0.20,
    upper: float = 0.50,
) -> SolveResult:
    """Solve the explicit-period uniform ROE implied by a market price.

    The terminal ROE and all other assumptions remain those in ``template``;
    only the explicit ROE path is replaced by the solved uniform value.
    """
    if target_price <= 0 or not isfinite(target_price):
        raise ValueError("target price must be finite and positive")

    def objective(roe: float) -> float:
        assumptions = ResidualIncomeAssumptions(
            opening_book_value_per_share=template.opening_book_value_per_share,
            roe_path=[roe] * len(template.roe_path),
            payout_ratio_path=template.payout_ratio_path,
            cost_of_equity=template.cost_of_equity,
            terminal_roe=template.terminal_roe,
            terminal_growth=template.terminal_growth,
        )
        return value_residual_income(assumptions).intrinsic_value_per_share - target_price

    return bounded_bisection(objective, lower, upper)
