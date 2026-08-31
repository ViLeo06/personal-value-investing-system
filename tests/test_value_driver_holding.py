import pytest

from value_investing.fcff import ValueDriverFcffAssumptions, value_driver_fcff
from value_investing.value_driver_holding import value_driver_holding_result


def test_value_driver_holding_revalues_remaining_cash_flows_at_horizon():
    operating = value_driver_fcff(
        ValueDriverFcffAssumptions(
            starting_revenue=100.0,
            starting_operating_margin=0.20,
            tax_rate=0.20,
            revenue_growth=(0.10, 0.09, 0.08, 0.07, 0.06, 0.05),
            operating_margins=(0.20,) * 6,
            ronic=(0.20,) * 6,
            wacc=0.10,
            terminal_growth=0.03,
            terminal_ronic=0.10,
        )
    )
    result = value_driver_holding_result(
        operating,
        discount_rate=0.10,
        equity_bridge_value=20.0,
        shares_outstanding=2.0,
        current_price=80.0,
        reporting_to_quote_fx=1.2,
        horizon_year=5,
        target_return=0.15,
    )
    expected_operating = (
        operating.forecast[5].fcff / 1.10
        + operating.terminal_value / 1.10
    )
    expected_per_share = (expected_operating + 20.0) / 2.0 * 1.2
    assert result.operating_value_at_horizon == pytest.approx(expected_operating)
    assert result.value_per_share_at_horizon == pytest.approx(expected_per_share)
    assert result.annualized_return == pytest.approx(
        (expected_per_share / 80.0) ** 0.2 - 1.0
    )
    assert result.target_buy_price == pytest.approx(expected_per_share / 1.15**5)


def test_value_driver_holding_rejects_invalid_horizon():
    operating = value_driver_fcff(
        ValueDriverFcffAssumptions(
            starting_revenue=100.0,
            starting_operating_margin=0.20,
            tax_rate=0.20,
            revenue_growth=(0.05,) * 5,
            operating_margins=(0.20,) * 5,
            ronic=(0.20,) * 5,
            wacc=0.10,
            terminal_growth=0.03,
            terminal_ronic=0.10,
        )
    )
    with pytest.raises(ValueError, match="horizon_year"):
        value_driver_holding_result(
            operating,
            discount_rate=0.10,
            equity_bridge_value=0.0,
            shares_outstanding=1.0,
            current_price=1.0,
            horizon_year=5,
        )
