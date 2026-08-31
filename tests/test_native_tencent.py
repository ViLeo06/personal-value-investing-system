import pytest

from value_investing.native_tencent import build_native_tencent_2021_run


def test_native_tencent_run_is_deterministic_and_not_tuned_to_legacy():
    run = build_native_tencent_2021_run()
    assert run.facts.inferred_weighted_average_shares_bn == pytest.approx(
        9.518963337547408
    )
    assert run.scenarios["pessimistic"].intrinsic_value_per_share_hkd == pytest.approx(
        247.17034956510244
    )
    assert run.scenarios["base"].intrinsic_value_per_share_hkd == pytest.approx(
        377.8300927535669
    )
    assert run.scenarios["optimistic"].intrinsic_value_per_share_hkd == pytest.approx(
        560.0272811360829
    )
    assert run.scenarios["base"].five_year_irr == pytest.approx(
        -0.008060123817144271
    )
    assert run.scenarios["base"].target_buy_price_15pct == pytest.approx(
        222.4011502768156
    )
    assert run.reverse_growth_multiplier.value == pytest.approx(
        1.5524930390984082
    )
    assert run.reverse_implied_first_year_growth == pytest.approx(
        0.20182409508279307
    )
    assert run.decision.signal == "avoid_at_price"
    assert run.native_minus_legacy_base_hkd < 0
    assert len(run.input_hash) == 64
    assert len(run.output_hash) == 64


def test_no_tencent_scenario_reaches_hurdle_at_2021_price():
    run = build_native_tencent_2021_run()
    assert max(output.five_year_irr for output in run.scenarios.values()) < 0.15
