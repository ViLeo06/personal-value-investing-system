import math

import pytest

from value_investing.fcff import (
    ValueDriverFcffAssumptions,
    equity_value_per_share,
    value_driver_fcff,
)


def test_fcff_forecast_reconciles():
    result = value_driver_fcff(
        ValueDriverFcffAssumptions(
            starting_revenue=1_000.0,
            starting_operating_margin=0.20,
            tax_rate=0.25,
            revenue_growth=[0.10, 0.08],
            operating_margins=[0.21, 0.22],
            ronic=[0.20, 0.18],
            wacc=0.10,
            terminal_growth=0.03,
            terminal_ronic=0.12,
        )
    )
    assert len(result.forecast) == 2
    assert result.forecast[0].fcff == pytest.approx(57.0)
    assert math.isclose(
        result.enterprise_value,
        result.pv_explicit_fcff + result.pv_terminal_value,
    )
    assert 0 < result.terminal_value_share < 1


def test_terminal_growth_requires_reinvestment_capacity():
    with pytest.raises(ValueError):
        value_driver_fcff(
            ValueDriverFcffAssumptions(
                starting_revenue=100.0,
                starting_operating_margin=0.20,
                tax_rate=0.25,
                revenue_growth=[0.05],
                operating_margins=[0.20],
                ronic=[0.10],
                wacc=0.09,
                terminal_growth=0.05,
                terminal_ronic=0.04,
            )
        )


def test_enterprise_to_equity_bridge():
    per_share = equity_value_per_share(
        1_000.0,
        cash_and_investments=200.0,
        debt=300.0,
        minority_interest=50.0,
        other_non_operating_assets=25.0,
        shares_outstanding=100.0,
    )
    assert per_share == pytest.approx(8.75)
