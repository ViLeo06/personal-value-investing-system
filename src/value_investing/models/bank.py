from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

from value_investing.valuation.core import bounded_bisection


@dataclass(frozen=True, slots=True)
class BankDriverYear:
    roe: float
    payout_ratio: float


@dataclass(frozen=True, slots=True)
class BankForecastYear:
    year: int
    opening_book_value: float
    net_income: float
    dividend: float
    residual_income: float
    closing_book_value: float


@dataclass(frozen=True, slots=True)
class ResidualIncomeResult:
    forecast: tuple[BankForecastYear, ...]
    present_value_residual_income: float
    present_value_terminal: float
    equity_value: float
    value_per_share: float


def residual_income_value(
    *,
    opening_book_value: float,
    shares_outstanding: float,
    drivers: Sequence[BankDriverYear],
    cost_of_equity: float,
    terminal_roe: float,
    terminal_growth: float,
) -> ResidualIncomeResult:
    if opening_book_value <= 0 or shares_outstanding <= 0:
        raise ValueError("book value and shares must be positive")
    if not drivers:
        raise ValueError("drivers cannot be empty")
    if cost_of_equity <= terminal_growth:
        raise ValueError("cost_of_equity must exceed terminal_growth")

    book_value = opening_book_value
    forecast: list[BankForecastYear] = []
    pv_residual = 0.0
    for year, driver in enumerate(drivers, 1):
        if not 0 <= driver.payout_ratio <= 1:
            raise ValueError("payout_ratio must be between 0 and 1")
        net_income = book_value * driver.roe
        dividend = net_income * driver.payout_ratio
        residual_income = net_income - book_value * cost_of_equity
        closing_book_value = book_value + net_income - dividend
        pv_residual += residual_income / ((1.0 + cost_of_equity) ** year)
        forecast.append(
            BankForecastYear(
                year=year,
                opening_book_value=book_value,
                net_income=net_income,
                dividend=dividend,
                residual_income=residual_income,
                closing_book_value=closing_book_value,
            )
        )
        book_value = closing_book_value

    terminal_residual_income = book_value * (terminal_roe - cost_of_equity)
    terminal_value = terminal_residual_income / (cost_of_equity - terminal_growth)
    pv_terminal = terminal_value / ((1.0 + cost_of_equity) ** len(drivers))
    equity_value = opening_book_value + pv_residual + pv_terminal
    return ResidualIncomeResult(
        forecast=tuple(forecast),
        present_value_residual_income=pv_residual,
        present_value_terminal=pv_terminal,
        equity_value=equity_value,
        value_per_share=equity_value / shares_outstanding,
    )


def implied_constant_roe(
    *,
    target_price: float,
    opening_book_value: float,
    shares_outstanding: float,
    years: int,
    payout_ratio: float,
    cost_of_equity: float,
    terminal_growth: float,
    lower: float = -0.10,
    upper: float = 0.40,
) -> float:
    """Reverse residual-income model using the same forward valuation function."""
    def residual(roe: float) -> float:
        result = residual_income_value(
            opening_book_value=opening_book_value,
            shares_outstanding=shares_outstanding,
            drivers=[BankDriverYear(roe=roe, payout_ratio=payout_ratio)] * years,
            cost_of_equity=cost_of_equity,
            terminal_roe=roe,
            terminal_growth=terminal_growth,
        )
        return result.value_per_share - target_price

    return bounded_bisection(residual, lower, upper)
