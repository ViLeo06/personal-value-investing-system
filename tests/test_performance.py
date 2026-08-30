from datetime import date

import pytest

from value_investing.performance import NavObservation, performance_summary


def test_performance_summary_and_drawdown():
    result = performance_summary(
        [
            NavObservation(date(2020, 1, 1), 100.0, 100.0),
            NavObservation(date(2020, 1, 2), 110.0, 101.0),
            NavObservation(date(2020, 1, 3), 88.0, 102.0),
            NavObservation(date(2021, 1, 1), 121.0, 110.0),
        ]
    )
    assert result.total_return == pytest.approx(0.21)
    assert result.maximum_drawdown == pytest.approx(-0.20)
    assert result.benchmark_total_return == pytest.approx(0.10)
    assert result.annualized_excess_return == pytest.approx(
        result.annualized_return - result.benchmark_annualized_return
    )
    assert result.annualized_volatility is not None


def test_partial_benchmark_series_is_rejected():
    with pytest.raises(ValueError, match="every row or none"):
        performance_summary(
            [
                NavObservation(date(2020, 1, 1), 100.0, 100.0),
                NavObservation(date(2020, 1, 2), 101.0, None),
            ]
        )


def test_unsorted_series_is_rejected():
    with pytest.raises(ValueError, match="chronological"):
        performance_summary(
            [
                NavObservation(date(2020, 1, 2), 101.0),
                NavObservation(date(2020, 1, 1), 100.0),
            ]
        )
