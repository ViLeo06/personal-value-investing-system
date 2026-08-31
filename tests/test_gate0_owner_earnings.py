import math
import pytest

from value_investing.gate0.owner_earnings import (
    DataSufficiencyError,
    OwnerEarningsInputs,
    Scenario,
    compute_owner_earnings,
    discounted_owner_earnings_value,
    implied_initial_growth,
    maximum_entry_price,
    validate_required_metrics,
)


def test_missing_inputs_block_valuation() -> None:
    with pytest.raises(DataSufficiencyError) as error:
        validate_required_metrics({"net_income_parent": 1.0})
    assert "maintenance_capex" in error.value.missing
    assert "shares_outstanding" in error.value.missing


def test_owner_earnings_bridge() -> None:
    inputs = OwnerEarningsInputs(
        net_income_parent=100.0,
        depreciation_amortization=15.0,
        other_non_cash_adjustments=2.0,
        maintenance_capex=10.0,
        change_working_capital=3.0,
    )
    assert compute_owner_earnings(inputs) == 104.0


def test_reverse_uses_same_forward_engine() -> None:
    scenario = Scenario(
        name="base",
        initial_growth=0.08,
        explicit_years=5,
        fade_years=5,
        terminal_growth=0.025,
        discount_rate=0.09,
        shares_outstanding=10.0,
        net_cash=50.0,
    )
    target = discounted_owner_earnings_value(100.0, scenario).value_per_share
    solved = implied_initial_growth(target, 100.0, scenario)
    assert math.isclose(solved, scenario.initial_growth, abs_tol=1e-8)


def test_invalid_terminal_assumption_is_rejected() -> None:
    scenario = Scenario(
        name="bad",
        initial_growth=0.05,
        explicit_years=5,
        fade_years=5,
        terminal_growth=0.09,
        discount_rate=0.09,
        shares_outstanding=10.0,
    )
    with pytest.raises(ValueError, match="discount_rate"):
        discounted_owner_earnings_value(100.0, scenario)


def test_maximum_entry_price_matches_present_value() -> None:
    result = maximum_entry_price(200.0, [5.0, 5.0], hurdle_rate=0.10)
    expected = 5.0 / 1.10 + 5.0 / (1.10**2) + 200.0 / (1.10**2)
    assert math.isclose(result, expected)
