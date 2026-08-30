import math

import pytest

from value_investing.fcff import (
    FcffAssumptions,
    five_year_irr as fcff_irr,
    implied_revenue_growth,
    target_buy_price as fcff_target,
    value_fcff,
)
from value_investing.residual_income import (
    ResidualIncomeAssumptions,
    economic_irr as residual_irr,
    implied_target_roe,
    target_buy_price as residual_target,
    value_residual_income,
)
from value_investing.value_driver_fcff import (
    ValueDriverAssumptions,
    implied_growth,
    value_value_driver,
)


def test_fcff_sotp_bridge_and_reverse_solver():
    assumptions = FcffAssumptions(
        starting_revenue=1000.0,
        first_five_year_revenue_growth=0.12,
        starting_operating_margin=0.20,
        target_operating_margin=0.24,
        tax_rate=0.20,
        sales_to_capital=1.5,
        discount_rate=0.095,
        perpetual_growth=0.025,
        terminal_ronic=0.12,
        non_operating_assets=250.0,
        net_debt=50.0,
        shares_outstanding=10.0,
    )
    result = value_fcff(assumptions)
    assert result.equity_value == pytest.approx(
        result.operating_enterprise_value + 200.0
    )
    assert 0 < result.terminal_value_share < 1
    market_price = result.intrinsic_value_per_share
    solved = implied_revenue_growth(market_price, assumptions)
    assert solved.converged
    assert solved.value == pytest.approx(0.12, abs=1e-8)
    assert fcff_target(result, 0.15) > 0
    assert math.isfinite(fcff_irr(market_price, result))


def test_fcff_terminal_value_requires_value_creating_ronic():
    with pytest.raises(ValueError):
        value_fcff(
            FcffAssumptions(
                starting_revenue=100.0,
                first_five_year_revenue_growth=0.05,
                starting_operating_margin=0.10,
                target_operating_margin=0.10,
                tax_rate=0.20,
                sales_to_capital=1.0,
                discount_rate=0.08,
                perpetual_growth=0.03,
                terminal_ronic=0.03,
            )
        )


def test_value_driver_identity_and_reverse_solver():
    assumptions = ValueDriverAssumptions(
        starting_nopat=100.0,
        first_five_year_growth=0.15,
        starting_ronic=0.25,
        terminal_ronic=0.10,
        discount_rate=0.10,
        perpetual_growth=0.025,
        net_debt=50.0,
        shares_outstanding=10.0,
    )
    result = value_value_driver(assumptions)
    first = result.years[0]
    assert first.reinvestment_rate == pytest.approx(first.growth / first.ronic)
    assert first.fcff == pytest.approx(first.nopat - first.reinvestment)
    solved = implied_growth(result.intrinsic_value_per_share, assumptions)
    assert solved.converged
    assert solved.value == pytest.approx(0.15, abs=1e-8)


def test_value_driver_rejects_growth_above_ronic():
    assumptions = ValueDriverAssumptions(
        starting_nopat=100.0,
        first_five_year_growth=0.30,
        starting_ronic=0.20,
        terminal_ronic=0.10,
        discount_rate=0.10,
        perpetual_growth=0.02,
    )
    with pytest.raises(ValueError):
        value_value_driver(assumptions)


def test_residual_income_equals_book_when_roe_equals_cost_of_equity():
    assumptions = ResidualIncomeAssumptions(
        beginning_book_value_per_share=20.0,
        starting_roe=0.10,
        target_roe=0.10,
        payout_ratio=0.40,
        cost_of_equity=0.10,
        perpetual_growth=0.03,
    )
    result = value_residual_income(assumptions)
    assert result.intrinsic_value_per_share == pytest.approx(20.0)
    assert result.pv_explicit_residual_income == pytest.approx(0.0)
    assert result.pv_terminal_value == pytest.approx(0.0)


def test_residual_income_reverse_solver_and_investor_cash_flows():
    assumptions = ResidualIncomeAssumptions(
        beginning_book_value_per_share=25.0,
        starting_roe=0.16,
        target_roe=0.13,
        payout_ratio=0.35,
        cost_of_equity=0.10,
        perpetual_growth=0.03,
    )
    result = value_residual_income(assumptions)
    solved = implied_target_roe(result.intrinsic_value_per_share, assumptions)
    assert solved.converged
    assert solved.value == pytest.approx(0.13, abs=1e-8)
    irr = residual_irr(result.intrinsic_value_per_share, result)
    assert irr.converged
    assert residual_target(result, 0.15) > 0
