import pytest

from value_investing.baselines import (
    PiotroskiInputs,
    ValueInputs,
    combined_value_quality_score,
    piotroski_f_score,
    value_metrics,
)


def test_piotroski_score_counts_nine_signals():
    result = piotroski_f_score(
        PiotroskiInputs(
            roa_current=0.10,
            roa_prior=0.08,
            operating_cash_flow_current=120.0,
            net_income_current=100.0,
            leverage_current=0.20,
            leverage_prior=0.25,
            current_ratio_current=1.5,
            current_ratio_prior=1.4,
            shares_current=100.0,
            shares_prior=100.0,
            gross_margin_current=0.40,
            gross_margin_prior=0.38,
            asset_turnover_current=1.2,
            asset_turnover_prior=1.1,
        )
    )
    assert result.score == 9
    assert len(result.signals) == 9


def test_value_metrics_are_transparent_yields():
    result = value_metrics(
        ValueInputs(
            market_cap=1_000.0,
            enterprise_value=1_200.0,
            ebit=120.0,
            free_cash_flow=80.0,
            book_equity=500.0,
        )
    )
    assert result.earnings_yield == pytest.approx(0.10)
    assert result.free_cash_flow_yield == pytest.approx(0.08)
    assert result.book_to_market == pytest.approx(0.50)


def test_combined_score_uses_value_and_quality():
    assert combined_value_quality_score(0.80, 9) == pytest.approx(0.90)
