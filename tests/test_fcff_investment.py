import pytest

from value_investing.fcff import ValueDriverFcffAssumptions, value_driver_fcff
from value_investing.fcff_investment import (
    fcff_enterprise_value_at_horizon,
    value_fcff_holding_period,
)


def _assumptions() -> ValueDriverFcffAssumptions:
    return ValueDriverFcffAssumptions(
        starting_revenue=1_000.0,
        starting_operating_margin=0.20,
        tax_rate=0.25,
        revenue_growth=[0.10] * 10,
        operating_margins=[0.20] * 10,
        ronic=[0.20] * 10,
        wacc=0.10,
        terminal_growth=0.03,
        terminal_ronic=0.12,
    )


def test_exit_enterprise_value_reconciles_to_remaining_cash_flows():
    assumptions = _assumptions()
    result = value_driver_fcff(assumptions)
    exit_ev = fcff_enterprise_value_at_horizon(result, assumptions)
    expected = sum(
        year.fcff / 1.10 ** (year.year - 5)
        for year in result.forecast
        if year.year > 5
    ) + result.terminal_value / 1.10**5
    assert exit_ev == pytest.approx(expected)


def test_holding_return_and_target_entry_share_same_exit_value():
    assumptions = _assumptions()
    result = value_driver_fcff(assumptions)
    holding = value_fcff_holding_period(
        12.0,
        result,
        assumptions,
        shares_outstanding=100.0,
        cash_and_investments_at_exit=100.0,
        debt_at_exit=150.0,
    )
    assert holding.enterprise_value_at_exit > 0
    assert holding.value_per_share_at_exit == pytest.approx(
        holding.equity_value_at_exit / 100.0
    )
    assert holding.target_entry_price == pytest.approx(
        holding.value_per_share_at_exit / 1.15**5
    )


def test_holding_horizon_must_precede_terminal_year():
    assumptions = _assumptions()
    result = value_driver_fcff(assumptions)
    with pytest.raises(ValueError):
        fcff_enterprise_value_at_horizon(result, assumptions, holding_years=10)
