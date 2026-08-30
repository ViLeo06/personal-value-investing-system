"""Deterministic normalization rules for bank residual-income models."""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite


@dataclass(frozen=True)
class BankNormalization:
    opening_book_value_per_share: float
    reported_annualized_roe: float
    annualized_eps: float
    net_interest_margin: float
    credit_cost: float
    cost_income_ratio: float
    non_performing_loan_ratio: float
    common_equity_tier1_ratio: float
    rule_version: str
    limitations: tuple[str, ...]


def normalize_cmb_residual_income_v1(
    *,
    book_value_per_share: float,
    annualized_roe: float,
    half_year_eps: float,
    net_interest_margin: float,
    credit_cost: float,
    cost_income_ratio: float,
    non_performing_loan_ratio: float,
    common_equity_tier1_ratio: float,
) -> BankNormalization:
    """Normalize CMB's 2021H1 bank facts without using post-cutoff results."""
    values = (
        book_value_per_share,
        annualized_roe,
        half_year_eps,
        net_interest_margin,
        credit_cost,
        cost_income_ratio,
        non_performing_loan_ratio,
        common_equity_tier1_ratio,
    )
    if not all(isfinite(value) for value in values):
        raise ValueError("normalization inputs must be finite")
    if book_value_per_share <= 0 or half_year_eps < 0:
        raise ValueError("book value must be positive and EPS non-negative")
    if not 0 <= annualized_roe < 1:
        raise ValueError("ROE must be in [0, 1)")
    ratios = {
        "net_interest_margin": net_interest_margin,
        "credit_cost": credit_cost,
        "cost_income_ratio": cost_income_ratio,
        "non_performing_loan_ratio": non_performing_loan_ratio,
        "common_equity_tier1_ratio": common_equity_tier1_ratio,
    }
    for name, value in ratios.items():
        if not 0 <= value < 1:
            raise ValueError(f"{name} must be in [0, 1)")

    return BankNormalization(
        opening_book_value_per_share=book_value_per_share,
        reported_annualized_roe=annualized_roe,
        annualized_eps=half_year_eps * 2.0,
        net_interest_margin=net_interest_margin,
        credit_cost=credit_cost,
        cost_income_ratio=cost_income_ratio,
        non_performing_loan_ratio=non_performing_loan_ratio,
        common_equity_tier1_ratio=common_equity_tier1_ratio,
        rule_version="cmb_residual_income_normalization_v1",
        limitations=(
            "half-year EPS is annualized only as a diagnostic and is not used as the residual-income starting book value",
            "reported annualized ROE is an anchor; explicit scenario ROE paths are policy assumptions",
            "the historical close and Phase-B corporate-action ledger remain provisional until official market files are archived",
        ),
    )
