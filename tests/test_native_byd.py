import pytest

from value_investing.native_byd import build_native_byd_2021_run


def test_native_byd_run_is_deterministic_and_not_tuned_to_legacy():
    run = build_native_byd_2021_run()
    assert run.facts.debt_rmb_bn == pytest.approx(41.273319)
    assert run.facts.equity_bridge_rmb_bn == pytest.approx(-28.151133)
    assert run.scenarios["pessimistic"].result.intrinsic_value_per_share == pytest.approx(
        -2.0041760547668135
    )
    assert run.scenarios["base"].result.intrinsic_value_per_share == pytest.approx(
        25.95616662450093
    )
    assert run.scenarios["optimistic"].result.intrinsic_value_per_share == pytest.approx(
        111.98746246951156
    )
    assert run.scenarios["base"].five_year_irr == pytest.approx(
        -0.2271602085438662
    )
    assert run.scenarios["base"].target_buy_price_15pct == pytest.approx(
        38.65103035476687
    )
    assert run.reverse_growth_multiplier.value == pytest.approx(
        3.183028538214785
    )
    assert run.reverse_implied_first_year_growth == pytest.approx(
        0.9549085614644355
    )
    assert run.decision.signal == "avoid_at_price"
    assert run.native_minus_legacy_base_cny > 0
    assert run.input_hash == (
        "d82e5d87e44d5b7be0f77cedb560f4291d27d29e632e7505e76ec01034876114"
    )
    assert run.output_hash == (
        "4d8cdea5db2e0c872aec2c738d3b94cda45ea1d962760d334ef0d15db8baff30"
    )


def test_byd_high_growth_case_exposes_reinvestment_burden():
    run = build_native_byd_2021_run()
    base = run.scenarios["base"].result
    assert base.operating_result.pv_explicit_fcff < 0
    assert base.terminal_value_share > 1.0
    assert max(output.five_year_irr for output in run.scenarios.values()) < 0.15
