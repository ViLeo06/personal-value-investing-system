import pytest

from value_investing.native_moutai import build_native_moutai_2021_run


def test_native_moutai_run_is_deterministic_and_not_tuned_to_legacy():
    run = build_native_moutai_2021_run()
    assert run.normalization.normalized_owner_earnings_per_share == pytest.approx(38.5177842)
    assert run.scenarios["pessimistic"].result.intrinsic_value_per_share == pytest.approx(
        603.0677888177593
    )
    assert run.scenarios["base"].result.intrinsic_value_per_share == pytest.approx(
        930.5299864767308
    )
    assert run.scenarios["optimistic"].result.intrinsic_value_per_share == pytest.approx(
        1435.342514370947
    )
    assert run.scenarios["base"].five_year_irr == pytest.approx(-0.023967490793221462)
    assert run.scenarios["base"].target_buy_price_15pct == pytest.approx(744.4695241484767)
    assert run.reverse_implied_growth == pytest.approx(0.1878917407584595)
    assert run.decision.signal == "avoid_at_price"
    assert run.native_minus_legacy_base < 0
    assert len(run.input_hash) == 64
    assert len(run.output_hash) == 64


def test_no_scenario_reaches_hurdle_at_2021_price():
    run = build_native_moutai_2021_run()
    assert max(output.five_year_irr for output in run.scenarios.values()) < 0.15
