import pytest

from value_investing.fcff import (
    ValueDriverFcffAssumptions,
    equity_value_per_share,
    value_driver_fcff,
)
from value_investing.market_expectations import (
    implied_platform_operating_growth,
    implied_uniform_fcff_growth,
)
from value_investing.sotp import SotPComponent, sum_of_the_parts


def _template(growth: float) -> ValueDriverFcffAssumptions:
    return ValueDriverFcffAssumptions(
        starting_revenue=1_000.0,
        starting_operating_margin=0.20,
        tax_rate=0.25,
        revenue_growth=[growth] * 5,
        operating_margins=[0.20] * 5,
        ronic=[0.20] * 5,
        wacc=0.10,
        terminal_growth=0.03,
        terminal_ronic=0.12,
    )


def test_reverse_fcff_recovers_forward_growth():
    true_growth = 0.08
    forward = value_driver_fcff(_template(true_growth))
    target = equity_value_per_share(
        forward.enterprise_value,
        cash_and_investments=100.0,
        debt=200.0,
        shares_outstanding=100.0,
    )
    solved = implied_uniform_fcff_growth(
        target,
        _template(0.01),
        cash_and_investments=100.0,
        debt=200.0,
        shares_outstanding=100.0,
    )
    assert solved.converged
    assert solved.value == pytest.approx(true_growth, abs=1e-7)


def test_reverse_platform_growth_keeps_investments_separate():
    true_growth = 0.06
    operating = value_driver_fcff(_template(true_growth)).enterprise_value
    investments = (SotPComponent("listed_associate", 500.0, ownership=0.40),)
    target = sum_of_the_parts(
        (SotPComponent("operating_business", operating),) + investments,
        non_operating_assets=50.0,
        debt=100.0,
        minority_interest=20.0,
        other_claims=10.0,
        shares_outstanding=100.0,
    ).value_per_share
    solved = implied_platform_operating_growth(
        target,
        _template(0.01),
        investment_components=investments,
        non_operating_assets=50.0,
        debt=100.0,
        minority_interest=20.0,
        other_claims=10.0,
        shares_outstanding=100.0,
    )
    assert solved.converged
    assert solved.value == pytest.approx(true_growth, abs=1e-7)
