import pytest

from value_investing.native_cmb import build_native_cmb_2021_run
from value_investing.residual_income_investment import (
    residual_income_investor_cash_flows,
)


def test_native_cmb_is_deterministic():
    run = build_native_cmb_2021_run()
    assert run.normalization.opening_book_value_per_share == pytest.approx(26.60)
    assert run.normalization.reported_annualized_roe == pytest.approx(0.1806)
    assert run.scenarios[
        "pessimistic"
    ].result.intrinsic_value_per_share == pytest.approx(20.69829893421815)
    assert run.scenarios["base"].result.intrinsic_value_per_share == pytest.approx(
        36.135509092814395
    )
    assert run.scenarios[
        "optimistic"
    ].result.intrinsic_value_per_share == pytest.approx(57.67577668835412)
    assert run.scenarios["base"].five_year_irr == pytest.approx(
        0.03755026696100423
    )
    assert run.scenarios["base"].target_buy_price_15pct == pytest.approx(
        30.067466242836502
    )
    assert run.reverse_implied_uniform_roe == pytest.approx(0.17671456246754852)
    assert run.decision.signal == "avoid_at_price"
    assert len(run.input_hash) == 64
    assert len(run.output_hash) == 64


def test_residual_income_exit_value_reconciles_investor_flows():
    run = build_native_cmb_2021_run()
    output = run.scenarios["base"]
    flows = residual_income_investor_cash_flows(
        run.current_price,
        output.result,
        output.assumptions,
    )
    assert len(flows) == 6
    assert flows[-1] == pytest.approx(
        output.result.forecast[4].dividend_per_share
        + output.year_five_value_per_share
    )


def test_price_implies_near_reported_high_roe():
    run = build_native_cmb_2021_run()
    assert run.reverse_implied_uniform_roe == pytest.approx(
        run.normalization.reported_annualized_roe,
        abs=0.005,
    )
    assert max(output.five_year_irr for output in run.scenarios.values()) < 0.15
