import math

import pytest

from value_investing.residual_income import (
    ResidualIncomeAssumptions,
    implied_uniform_roe,
    value_residual_income,
)


def test_residual_income_reconciles():
    result = value_residual_income(
        ResidualIncomeAssumptions(
            opening_book_value_per_share=10.0,
            roe_path=[0.15, 0.14],
            payout_ratio_path=[0.40, 0.40],
            cost_of_equity=0.10,
            terminal_roe=0.11,
            terminal_growth=0.03,
        )
    )
    assert result.intrinsic_value_per_share > result.opening_book_value_per_share
    assert math.isclose(
        result.intrinsic_value_per_share,
        result.opening_book_value_per_share
        + result.pv_explicit_residual_income
        + result.pv_terminal_residual_income,
    )
    assert len(result.forecast) == 2


def test_value_equals_book_when_roe_equals_cost_of_equity():
    result = value_residual_income(
        ResidualIncomeAssumptions(
            opening_book_value_per_share=20.0,
            roe_path=[0.10] * 5,
            payout_ratio_path=[0.35] * 5,
            cost_of_equity=0.10,
            terminal_roe=0.10,
            terminal_growth=0.03,
        )
    )
    assert result.intrinsic_value_per_share == pytest.approx(20.0)


def test_reverse_implied_uniform_roe_uses_forward_model():
    target_assumptions = ResidualIncomeAssumptions(
        opening_book_value_per_share=10.0,
        roe_path=[0.15] * 5,
        payout_ratio_path=[0.40] * 5,
        cost_of_equity=0.10,
        terminal_roe=0.10,
        terminal_growth=0.03,
    )
    target = value_residual_income(target_assumptions).intrinsic_value_per_share
    result = implied_uniform_roe(target, target_assumptions)
    assert result.converged
    assert result.value == pytest.approx(0.15, abs=1e-7)
