import pytest

from value_investing.bank import (
    BankOperatingDiagnostics,
    BankScenarioAssumptions,
    value_bank_scenario,
)
from value_investing.fcff import ValueDriverFcffAssumptions
from value_investing.manufacturing import (
    ManufacturingScenarioAssumptions,
    value_manufacturing_scenario,
)
from value_investing.platform import PlatformScenarioAssumptions, value_platform_scenario
from value_investing.residual_income import ResidualIncomeAssumptions
from value_investing.sotp import SotPComponent


def _operating() -> ValueDriverFcffAssumptions:
    return ValueDriverFcffAssumptions(
        starting_revenue=1_000.0,
        starting_operating_margin=0.20,
        tax_rate=0.25,
        revenue_growth=[0.08] * 5,
        operating_margins=[0.20] * 5,
        ronic=[0.20] * 5,
        wacc=0.10,
        terminal_growth=0.03,
        terminal_ronic=0.12,
    )


def test_platform_keeps_investment_assets_outside_operating_fcff():
    result = value_platform_scenario(
        PlatformScenarioAssumptions(
            operating=_operating(),
            investment_components=(
                SotPComponent("associate", 500.0, ownership=0.40),
            ),
            non_operating_assets=50.0,
            debt=100.0,
            minority_interest=20.0,
            other_claims=10.0,
            shares_outstanding=100.0,
        )
    )
    assert result.investment_value_share == pytest.approx(2.0)
    assert result.bridge_value_share == pytest.approx(-0.8)
    assert result.intrinsic_value_per_share == pytest.approx(
        result.operating_value_share + 2.0 - 0.8
    )


def test_manufacturing_reports_ronic_quality():
    result = value_manufacturing_scenario(
        ManufacturingScenarioAssumptions(
            operating=_operating(),
            cash_and_investments=100.0,
            debt=200.0,
            minority_interest=10.0,
            other_non_operating_assets=20.0,
            shares_outstanding=100.0,
        )
    )
    assert result.explicit_average_ronic == pytest.approx(0.20)
    assert result.terminal_ronic_spread == pytest.approx(0.02)


def test_bank_wrapper_bridges_other_equity_claims():
    result = value_bank_scenario(
        BankScenarioAssumptions(
            residual_income=ResidualIncomeAssumptions(
                opening_book_value_per_share=20.0,
                roe_path=[0.14] * 5,
                payout_ratio_path=[0.35] * 5,
                cost_of_equity=0.10,
                terminal_roe=0.11,
                terminal_growth=0.03,
            ),
            diagnostics=BankOperatingDiagnostics(net_interest_margin=0.025),
            other_equity_claims_per_share=1.0,
        )
    )
    assert result.intrinsic_common_value_per_share == pytest.approx(
        result.residual_income_result.intrinsic_value_per_share - 1.0
    )
    assert result.price_to_book_value > 1.0
