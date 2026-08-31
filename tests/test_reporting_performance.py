from datetime import date
import math

import pytest

from value_investing.reporting.performance import (
    reconcile_attribution,
    summarize_performance,
)


def test_total_return_cagr_and_drawdown() -> None:
    summary = summarize_performance(
        {
            date(2020, 1, 1): 100.0,
            date(2020, 6, 1): 80.0,
            date(2021, 1, 1): 121.0,
        },
        periods_per_year=2,
    )
    assert math.isclose(summary.total_return, 0.21)
    assert math.isclose(summary.cagr, 0.21, rel_tol=0.01)
    assert math.isclose(summary.max_drawdown, -0.20)
    assert summary.annualized_volatility is not None


def test_benchmark_metrics_use_common_dates() -> None:
    summary = summarize_performance(
        {
            date(2020, 1, 1): 100.0,
            date(2020, 2, 1): 110.0,
            date(2020, 3, 1): 121.0,
        },
        benchmark_nav_by_date={
            date(2020, 1, 1): 100.0,
            date(2020, 2, 1): 105.0,
            date(2020, 3, 1): 110.25,
        },
        periods_per_year=12,
    )
    assert math.isclose(summary.benchmark_total_return or 0.0, 0.1025)
    assert math.isclose(summary.excess_total_return or 0.0, 0.1075)
    assert summary.tracking_error is not None


def test_attribution_reconciliation() -> None:
    residual = reconcile_attribution(
        total_return=0.25,
        effects={"price": 0.20, "dividend": 0.05, "fees": 0.0},
    )
    assert math.isclose(residual, 0.0)


def test_attribution_mismatch_is_rejected() -> None:
    with pytest.raises(ValueError, match="does not reconcile"):
        reconcile_attribution(
            total_return=0.25,
            effects={"price": 0.20, "dividend": 0.04},
        )
