from datetime import date
import math

from value_investing.attribution.returns import attribute_equity_return
from value_investing.backtest.walk_forward import Cohort, mature_cohorts, non_overlapping_cohorts
from value_investing.decision.policy import DecisionInput, DecisionStatus, decide
from value_investing.model_router import route_model


def test_incomplete_data_cannot_produce_buy_decision() -> None:
    result = decide(
        DecisionInput(
            reference_price=60.0,
            base_intrinsic_value=100.0,
            expected_exit_price=120.0,
            expected_dividends=(2.0,) * 5,
            data_quality_pass=False,
        )
    )
    assert result.status == DecisionStatus.INSUFFICIENT_DATA
    assert result.expected_irr is None


def test_valid_case_can_meet_hurdle_and_margin_of_safety() -> None:
    result = decide(
        DecisionInput(
            reference_price=60.0,
            base_intrinsic_value=100.0,
            expected_exit_price=120.0,
            expected_dividends=(2.0,) * 5,
            hurdle_rate=0.15,
            minimum_margin_of_safety=0.20,
        )
    )
    assert result.status == DecisionStatus.BUY_CANDIDATE
    assert result.expected_irr is not None
    assert result.expected_irr >= 0.15


def test_router_maps_initial_four_model_families() -> None:
    assert route_model("owner_earnings_dcf").primary_module.endswith("consumer")
    assert route_model("fcff_sotp").primary_module.endswith("platform")
    assert route_model("value_driver_fcff").primary_module.endswith("manufacturing")
    assert route_model("residual_income").primary_module.endswith("bank")


def test_mature_and_non_overlapping_cohorts_are_reported_separately() -> None:
    cohorts = [
        Cohort("2015", date(2015, 4, 1), 5),
        Cohort("2016", date(2016, 4, 1), 5),
        Cohort("2021", date(2021, 4, 1), 5),
    ]
    mature = mature_cohorts(cohorts, date(2026, 8, 30))
    assert [cohort.cohort_id for cohort in mature] == ["2015", "2016", "2021"]
    independent = non_overlapping_cohorts(mature)
    assert [cohort.cohort_id for cohort in independent] == ["2015", "2021"]


def test_price_and_fx_attribution_reconciles() -> None:
    result = attribute_equity_return(
        quantity=100.0,
        opening_price_local=10.0,
        closing_price_local=12.0,
        opening_fx_to_base=0.90,
        closing_fx_to_base=0.85,
        dividends_base=15.0,
        fees_base=2.0,
    )
    assert math.isclose(result.residual, 0.0, abs_tol=1e-10)
