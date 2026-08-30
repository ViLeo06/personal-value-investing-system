import pytest

from value_investing.sotp import SotPComponent, sum_of_the_parts


def test_sotp_bridge_and_component_discounts():
    result = sum_of_the_parts(
        [
            SotPComponent("core", 100.0),
            SotPComponent("associate", 200.0, ownership=0.50, holding_discount=0.10),
        ],
        non_operating_assets=30.0,
        debt=50.0,
        minority_interest=10.0,
        other_claims=5.0,
        shares_outstanding=10.0,
    )
    assert result.component_value == pytest.approx(190.0)
    assert result.equity_value == pytest.approx(155.0)
    assert result.value_per_share == pytest.approx(15.5)


def test_sotp_rejects_invalid_ownership():
    with pytest.raises(ValueError):
        sum_of_the_parts(
            [SotPComponent("bad", 100.0, ownership=1.1)],
            shares_outstanding=10.0,
        )
