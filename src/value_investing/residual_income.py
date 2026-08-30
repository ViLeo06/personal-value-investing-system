"""Residual-income valuation primitives for banks and financial firms.

The public assumptions object accepts either an explicit ROE/payout path or a
compact scenario (starting ROE, target ROE and a constant payout ratio).  Both
routes are expanded into the same deterministic forward model, so reverse
solves and investor-return helpers cannot drift from the valuation engine.
"""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite
from typing import Sequence

from .valuation import SolveResult, bounded_bisection, present_value


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


@dataclass(frozen=True, init=False)
class ResidualIncomeAssumptions:
    """Canonical residual-income assumptions with two compatible constructors.

    Explicit-path form::

        ResidualIncomeAssumptions(
            opening_book_value_per_share=...,
            roe_path=[...],
            payout_ratio_path=[...],
            cost_of_equity=...,
            terminal_roe=...,
            terminal_growth=...,
        )

    Compact form::

        ResidualIncomeAssumptions(
            beginning_book_value_per_share=...,
            starting_roe=...,
            target_roe=...,
            payout_ratio=...,
            cost_of_equity=...,
            perpetual_growth=...,
        )

    The compact form linearly moves ROE from ``starting_roe`` in year one to
    ``target_roe`` in year five, then holds the target through the rest of the
    explicit period.  It is only a convenience constructor; the stored state is
    always the explicit canonical path.
    """

    opening_book_value_per_share: float
    roe_path: tuple[float, ...]
    payout_ratio_path: tuple[float, ...]
    cost_of_equity: float
    terminal_roe: float
    terminal_growth: float

    def __init__(
        self,
        *,
        opening_book_value_per_share: float | None = None,
        roe_path: Sequence[float] | None = None,
        payout_ratio_path: Sequence[float] | None = None,
        cost_of_equity: float,
        terminal_roe: float | None = None,
        terminal_growth: float | None = None,
        beginning_book_value_per_share: float | None = None,
        starting_roe: float | None = None,
        target_roe: float | None = None,
        payout_ratio: float | None = None,
        perpetual_growth: float | None = None,
        explicit_years: int = 10,
        transition_years: int = 5,
    ) -> None:
        explicit_requested = any(
            value is not None
            for value in (
                opening_book_value_per_share,
                roe_path,
                payout_ratio_path,
                terminal_roe,
                terminal_growth,
            )
        )
        compact_requested = any(
            value is not None
            for value in (
                beginning_book_value_per_share,
                starting_roe,
                target_roe,
                payout_ratio,
                perpetual_growth,
            )
        )
        if explicit_requested and compact_requested:
            raise ValueError("do not mix explicit-path and compact assumptions")

        if explicit_requested:
            required = (
                opening_book_value_per_share,
                roe_path,
                payout_ratio_path,
                terminal_roe,
                terminal_growth,
            )
            if any(value is None for value in required):
                raise ValueError("explicit-path assumptions are incomplete")
            opening = float(opening_book_value_per_share)
            roes = tuple(float(value) for value in roe_path or ())
            payouts = tuple(float(value) for value in payout_ratio_path or ())
            terminal_roe_value = float(terminal_roe)
            terminal_growth_value = float(terminal_growth)
        elif compact_requested:
            required = (
                beginning_book_value_per_share,
                starting_roe,
                target_roe,
                payout_ratio,
                perpetual_growth,
            )
            if any(value is None for value in required):
                raise ValueError("compact assumptions are incomplete")
            if explicit_years < 5:
                raise ValueError("explicit_years must be at least five")
            if not 2 <= transition_years <= explicit_years:
                raise ValueError("transition_years must fall inside explicit years")
            opening = float(beginning_book_value_per_share)
            start = float(starting_roe)
            target = float(target_roe)
            roes = tuple(
                start
                + (target - start)
                * min(year - 1, transition_years - 1)
                / (transition_years - 1)
                for year in range(1, explicit_years + 1)
            )
            payouts = (float(payout_ratio),) * explicit_years
            terminal_roe_value = target
            terminal_growth_value = float(perpetual_growth)
        else:
            raise ValueError("provide either explicit-path or compact assumptions")

        object.__setattr__(self, "opening_book_value_per_share", opening)
        object.__setattr__(self, "roe_path", roes)
        object.__setattr__(self, "payout_ratio_path", payouts)
        object.__setattr__(self, "cost_of_equity", float(cost_of_equity))
        object.__setattr__(self, "terminal_roe", terminal_roe_value)
        object.__setattr__(self, "terminal_growth", terminal_growth_value)

    @property
    def beginning_book_value_per_share(self) -> float:
        """Compatibility alias used by the compact model-family contract."""
        return self.opening_book_value_per_share


@dataclass(frozen=True)
class ResidualIncomeResult:
    intrinsic_value_per_share: float
    opening_book_value_per_share: float
    pv_explicit_residual_income: float
    pv_terminal_residual_income: float
    terminal_residual_income_value: float
    terminal_value_share: float
    forecast: tuple[ResidualIncomeYear, ...]

    @property
    def pv_terminal_value(self) -> float:
        """Compatibility alias for the compact model-family result contract."""
        return self.pv_terminal_residual_income


def _validate(assumptions: ResidualIncomeAssumptions) -> None:
    if not assumptions.roe_path or len(assumptions.roe_path) != len(
        assumptions.payout_ratio_path
    ):
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
    """Solve the explicit-period uniform ROE implied by a market price."""
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


def implied_target_roe(
    target_price: float,
    template: ResidualIncomeAssumptions,
    *,
    lower_bound: float = -0.20,
    upper_bound: float = 0.50,
) -> SolveResult:
    """Solve the compact scenario's explicit/terminal target ROE."""
    if target_price <= 0 or not isfinite(target_price):
        raise ValueError("target price must be finite and positive")
    if not template.roe_path:
        raise ValueError("template must have an explicit ROE path")
    starting_roe = template.roe_path[0]
    payout_ratio = template.payout_ratio_path[0]
    explicit_years = len(template.roe_path)
    transition_years = min(5, explicit_years)

    def objective(target_roe: float) -> float:
        assumptions = ResidualIncomeAssumptions(
            beginning_book_value_per_share=template.opening_book_value_per_share,
            starting_roe=starting_roe,
            target_roe=target_roe,
            payout_ratio=payout_ratio,
            cost_of_equity=template.cost_of_equity,
            perpetual_growth=template.terminal_growth,
            explicit_years=explicit_years,
            transition_years=transition_years,
        )
        return value_residual_income(assumptions).intrinsic_value_per_share - target_price

    return bounded_bisection(objective, lower_bound, upper_bound, tolerance=1e-11)


def _cost_of_equity_from_result(result: ResidualIncomeResult) -> float:
    if not result.forecast:
        raise ValueError("result must contain an explicit forecast")
    first = result.forecast[0]
    if first.opening_book_value_per_share <= 0:
        raise ValueError("opening book value must be positive")
    return first.roe - (
        first.residual_income_per_share / first.opening_book_value_per_share
    )


def _holding_value(
    result: ResidualIncomeResult,
    *,
    holding_years: int = 5,
) -> float:
    if not 1 <= holding_years < len(result.forecast):
        raise ValueError("holding years must fall inside the explicit forecast")
    cost_of_equity = _cost_of_equity_from_result(result)
    closing_book = result.forecast[holding_years - 1].closing_book_value_per_share
    continuing_residual_income = sum(
        present_value(
            row.residual_income_per_share,
            cost_of_equity,
            row.year - holding_years,
        )
        for row in result.forecast[holding_years:]
    )
    terminal = present_value(
        result.terminal_residual_income_value,
        cost_of_equity,
        len(result.forecast) - holding_years,
    )
    return closing_book + continuing_residual_income + terminal


def _investor_cash_flows(
    current_price: float,
    result: ResidualIncomeResult,
    *,
    holding_years: int = 5,
) -> tuple[float, ...]:
    if current_price <= 0 or not isfinite(current_price):
        raise ValueError("current price must be finite and positive")
    if not 1 <= holding_years < len(result.forecast):
        raise ValueError("holding years must fall inside the explicit forecast")
    flows = [-current_price]
    flows.extend(row.dividend_per_share for row in result.forecast[: holding_years - 1])
    flows.append(
        result.forecast[holding_years - 1].dividend_per_share
        + _holding_value(result, holding_years=holding_years)
    )
    return tuple(flows)


def _npv(rate: float, cash_flows: Sequence[float]) -> float:
    if rate <= -1:
        raise ValueError("IRR rate must be greater than -100%")
    return sum(
        cash_flow / ((1.0 + rate) ** period)
        for period, cash_flow in enumerate(cash_flows)
    )


def economic_irr(
    current_price: float,
    result: ResidualIncomeResult,
    *,
    holding_years: int = 5,
) -> SolveResult:
    """Solve annualized investor return from dividends and modeled exit value."""
    flows = _investor_cash_flows(
        current_price,
        result,
        holding_years=holding_years,
    )
    return bounded_bisection(
        lambda rate: _npv(rate, flows),
        -0.999999,
        10.0,
        tolerance=1e-12,
    )


def target_buy_price(
    result: ResidualIncomeResult,
    target_return: float = 0.15,
    *,
    holding_years: int = 5,
) -> float:
    """Price today that makes modeled dividends and exit meet the hurdle."""
    if target_return <= -1:
        raise ValueError("target return must be greater than -100%")
    future_flows = _investor_cash_flows(
        1.0,
        result,
        holding_years=holding_years,
    )[1:]
    return sum(
        present_value(value, target_return, year)
        for year, value in enumerate(future_flows, start=1)
    )
