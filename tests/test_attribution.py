import math

import pytest

from value_investing.attribution import (
    ReturnAttributionInput,
    attribute_total_return,
    forecast_error_table,
)


def test_multiplicative_attribution_reconstructs_total_return():
    result = attribute_total_return(
        ReturnAttributionInput(
            operating_metric_start=10.0,
            operating_metric_end=15.0,
            valuation_multiple_start=20.0,
            valuation_multiple_end=15.0,
            dividend_reinvestment_factor=1.10,
            fx_factor=0.95,
            other_per_share_factor=1.02,
        )
    )
    expected = 1.5 * 0.75 * 1.10 * 0.95 * 1.02
    assert result.total_factor == pytest.approx(expected)
    assert result.reconstructed_factor() == pytest.approx(expected)
    assert sum(result.log_contributions.values()) == pytest.approx(math.log(expected))
    assert sum(result.contribution_shares.values()) == pytest.approx(1.0)


def test_flat_total_return_has_zero_contribution_shares():
    result = attribute_total_return(
        ReturnAttributionInput(
            operating_metric_start=10,
            operating_metric_end=10,
            valuation_multiple_start=5,
            valuation_multiple_end=5,
        )
    )
    assert result.total_return == pytest.approx(0.0)
    assert set(result.contribution_shares.values()) == {0.0}


def test_invalid_nonpositive_factor_fails():
    with pytest.raises(ValueError):
        attribute_total_return(
            ReturnAttributionInput(
                operating_metric_start=0,
                operating_metric_end=10,
                valuation_multiple_start=5,
                valuation_multiple_end=5,
            )
        )


def test_forecast_error_table_is_aligned_and_unit_checked():
    rows = forecast_error_table(
        {
            "revenue": (100.0, "CNY"),
            "roe": (0.15, "ratio"),
        },
        {
            "revenue": (110.0, "CNY"),
            "roe": (0.12, "ratio"),
        },
    )
    assert tuple(row.metric for row in rows) == ("revenue", "roe")
    assert rows[0].absolute_error == pytest.approx(10.0)
    assert rows[0].relative_error == pytest.approx(0.10)

    with pytest.raises(ValueError):
        forecast_error_table(
            {"revenue": (100.0, "CNY")},
            {"revenue": (100.0, "HKD")},
        )
    with pytest.raises(ValueError):
        forecast_error_table(
            {"revenue": (100.0, "CNY")},
            {"profit": (100.0, "CNY")},
        )
