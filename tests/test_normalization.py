import pytest

from value_investing.normalization import (
    infer_shares_from_net_income_and_eps,
    normalize_moutai_owner_earnings_v1,
)


def test_infer_shares():
    assert infer_shares_from_net_income_and_eps(
        46_697_285_429.81, 37.17
    ) == pytest.approx(1_256_316_530.2612321)


def test_normalization_uses_only_pre_cutoff_inputs():
    result = normalize_moutai_owner_earnings_v1(
        net_income_2020=46_697_285_429.81,
        basic_eps_2020=37.17,
        operating_cash_flow_2020=51_669_068_693.03,
        net_income_h1_2021=24_653_985_551.58,
        operating_cash_flow_h1_2021=21_719_470_732.97,
        revenue_growth_h1_2021=0.1168,
        net_income_growth_h1_2021=0.0908,
    )
    assert result.growth_anchor == pytest.approx(0.1038)
    assert result.normalized_owner_earnings_per_share == pytest.approx(38.5177842)
    assert result.rule_version == "moutai_owner_earnings_normalization_v1"
