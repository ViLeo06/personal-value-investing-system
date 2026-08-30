import pytest

from value_investing.owner_earnings import (
    OwnerEarningsAssumptions,
    economic_irr,
    implied_first_five_year_growth,
    target_buy_price,
    value_owner_earnings,
)


@pytest.mark.parametrize(
    ("growth", "discount", "terminal", "expected_value", "expected_year5", "expected_irr", "expected_buy"),
    [
        (0.00, 0.105, 0.020, 678.2392699569455, 728.8950322601252, -0.047883001186962204, 573.5754236889491),
        (0.04, 0.090, 0.025, 1081.6558558683628, 1242.3507436009254, 0.04678180959257583, 853.0088662554501),
        (0.07, 0.080, 0.030, 1639.4590855661786, 1958.7639161271404, 0.13640728075725295, 1228.9008782351052),
    ],
)
def test_moutai_v11_golden_scenarios(
    growth, discount, terminal, expected_value, expected_year5, expected_irr, expected_buy
):
    assumptions = OwnerEarningsAssumptions(63.0, growth, discount, terminal)
    result = value_owner_earnings(assumptions)
    assert result.intrinsic_value_per_share == pytest.approx(expected_value, abs=1e-9)
    assert result.year_five_value_per_share == pytest.approx(expected_year5, abs=1e-9)
    irr = economic_irr(1297.4, result)
    assert irr.converged
    assert irr.value == pytest.approx(expected_irr, abs=1e-10)
    assert target_buy_price(result, 0.15) == pytest.approx(expected_buy, abs=1e-9)


def test_moutai_v11_reverse_dcf_uses_same_forward_model():
    template = OwnerEarningsAssumptions(63.0, 0.04, 0.09, 0.025)
    solved = implied_first_five_year_growth(1297.4, template, lower_bound=-0.05, upper_bound=0.20)
    assert solved.converged
    assert solved.value == pytest.approx(0.0725, abs=0.0013)
    rerun = value_owner_earnings(
        OwnerEarningsAssumptions(63.0, solved.value, 0.09, 0.025)
    )
    assert rerun.intrinsic_value_per_share == pytest.approx(1297.4, abs=1e-7)


def test_terminal_share_is_explicit():
    result = value_owner_earnings(OwnerEarningsAssumptions(63.0, 0.04, 0.09, 0.025))
    assert result.terminal_value_share == pytest.approx(
        result.present_value_terminal / result.intrinsic_value_per_share
    )
    assert 0 < result.terminal_value_share < 1
