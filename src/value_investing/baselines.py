"""Simple benchmark models used to challenge the complex valuation system."""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite


@dataclass(frozen=True)
class PiotroskiInputs:
    roa_current: float
    roa_prior: float
    operating_cash_flow_current: float
    net_income_current: float
    leverage_current: float
    leverage_prior: float
    current_ratio_current: float
    current_ratio_prior: float
    shares_current: float
    shares_prior: float
    gross_margin_current: float
    gross_margin_prior: float
    asset_turnover_current: float
    asset_turnover_prior: float


@dataclass(frozen=True)
class PiotroskiResult:
    score: int
    signals: tuple[tuple[str, int], ...]


@dataclass(frozen=True)
class ValueInputs:
    market_cap: float
    enterprise_value: float
    ebit: float
    free_cash_flow: float
    book_equity: float


@dataclass(frozen=True)
class ValueResult:
    earnings_yield: float
    free_cash_flow_yield: float
    book_to_market: float


def piotroski_f_score(inputs: PiotroskiInputs) -> PiotroskiResult:
    values = tuple(inputs.__dict__.values())
    if not all(isfinite(value) for value in values):
        raise ValueError("Piotroski inputs must be finite")
    if inputs.shares_current <= 0 or inputs.shares_prior <= 0:
        raise ValueError("share counts must be positive")

    signals = (
        ("positive_roa", int(inputs.roa_current > 0)),
        ("positive_operating_cash_flow", int(inputs.operating_cash_flow_current > 0)),
        ("improving_roa", int(inputs.roa_current > inputs.roa_prior)),
        ("cash_flow_exceeds_income", int(inputs.operating_cash_flow_current > inputs.net_income_current)),
        ("lower_leverage", int(inputs.leverage_current < inputs.leverage_prior)),
        ("improving_liquidity", int(inputs.current_ratio_current > inputs.current_ratio_prior)),
        ("no_equity_dilution", int(inputs.shares_current <= inputs.shares_prior)),
        ("improving_gross_margin", int(inputs.gross_margin_current > inputs.gross_margin_prior)),
        ("improving_asset_turnover", int(inputs.asset_turnover_current > inputs.asset_turnover_prior)),
    )
    return PiotroskiResult(sum(value for _, value in signals), signals)


def value_metrics(inputs: ValueInputs) -> ValueResult:
    values = tuple(inputs.__dict__.values())
    if not all(isfinite(value) for value in values):
        raise ValueError("value inputs must be finite")
    if inputs.market_cap <= 0 or inputs.enterprise_value <= 0:
        raise ValueError("market cap and enterprise value must be positive")
    return ValueResult(
        earnings_yield=inputs.ebit / inputs.enterprise_value,
        free_cash_flow_yield=inputs.free_cash_flow / inputs.market_cap,
        book_to_market=inputs.book_equity / inputs.market_cap,
    )


def combined_value_quality_score(
    value_percentile: float,
    f_score: int,
    *,
    value_weight: float = 0.5,
) -> float:
    if not all(isfinite(value) for value in (value_percentile, value_weight)):
        raise ValueError("combined-score inputs must be finite")
    if not 0 <= value_percentile <= 1:
        raise ValueError("value percentile must be in [0, 1]")
    if not 0 <= f_score <= 9:
        raise ValueError("F-score must be in [0, 9]")
    if not 0 <= value_weight <= 1:
        raise ValueError("value weight must be in [0, 1]")
    quality_percentile = f_score / 9.0
    return value_weight * value_percentile + (1.0 - value_weight) * quality_percentile
