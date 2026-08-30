"""Transparent fundamental normalization rules.

Normalization rules are deterministic and versioned. They do not contain
security prices or desired investment conclusions.
"""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite


@dataclass(frozen=True)
class OwnerEarningsNormalization:
    shares_outstanding: float
    observed_revenue_growth: float
    observed_net_income_growth: float
    growth_anchor: float
    normalized_owner_earnings_per_share: float
    cash_conversion_2020: float
    cash_conversion_h1_2021: float
    maintenance_reserve_factor: float
    rule_version: str
    limitations: tuple[str, ...]


def infer_shares_from_net_income_and_eps(net_income: float, eps: float) -> float:
    """Infer weighted-average shares from net income divided by basic EPS."""
    if not (isfinite(net_income) and isfinite(eps)):
        raise ValueError("net income and EPS must be finite")
    if net_income <= 0 or eps <= 0:
        raise ValueError("net income and EPS must be positive")
    return net_income / eps


def normalize_moutai_owner_earnings_v1(
    *,
    net_income_2020: float,
    basic_eps_2020: float,
    operating_cash_flow_2020: float,
    net_income_h1_2021: float,
    operating_cash_flow_h1_2021: float,
    revenue_growth_h1_2021: float,
    net_income_growth_h1_2021: float,
    maintenance_reserve_factor: float = 0.95,
) -> OwnerEarningsNormalization:
    """Build a conservative, PIT-safe Moutai owner-earnings starting point.

    The rule deliberately avoids using full-year 2021 results. It rolls the
    2020 audited EPS forward by the H1 net-income growth rate and deducts a
    fixed maintenance-capital reserve. Operating cash flow is retained as a
    diagnostic rather than the direct starting value because Moutai's finance
    subsidiary and seasonal working-capital movements can distort interim OCF.
    """
    numeric = (
        net_income_2020,
        basic_eps_2020,
        operating_cash_flow_2020,
        net_income_h1_2021,
        operating_cash_flow_h1_2021,
        revenue_growth_h1_2021,
        net_income_growth_h1_2021,
        maintenance_reserve_factor,
    )
    if not all(isfinite(value) for value in numeric):
        raise ValueError("normalization inputs must be finite")
    if not 0 < maintenance_reserve_factor <= 1:
        raise ValueError("maintenance reserve factor must be in (0, 1]")
    if revenue_growth_h1_2021 <= -1 or net_income_growth_h1_2021 <= -1:
        raise ValueError("growth rates must exceed -100%")

    shares = infer_shares_from_net_income_and_eps(net_income_2020, basic_eps_2020)
    growth_anchor = (revenue_growth_h1_2021 + net_income_growth_h1_2021) / 2.0
    normalized_eps = basic_eps_2020 * (1.0 + net_income_growth_h1_2021)
    normalized_owner_earnings = normalized_eps * maintenance_reserve_factor

    return OwnerEarningsNormalization(
        shares_outstanding=shares,
        observed_revenue_growth=revenue_growth_h1_2021,
        observed_net_income_growth=net_income_growth_h1_2021,
        growth_anchor=growth_anchor,
        normalized_owner_earnings_per_share=normalized_owner_earnings,
        cash_conversion_2020=operating_cash_flow_2020 / net_income_2020,
        cash_conversion_h1_2021=operating_cash_flow_h1_2021 / net_income_h1_2021,
        maintenance_reserve_factor=maintenance_reserve_factor,
        rule_version="moutai_owner_earnings_normalization_v1",
        limitations=(
            "maintenance capex is represented by a fixed 5% reserve, not a separately reported fact",
            "interim operating cash flow is diagnostic because finance-subsidiary deposits and seasonality can distort it",
            "no post-2021-08-30 full-year result is used",
        ),
    )
