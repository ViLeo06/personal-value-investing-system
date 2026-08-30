"""Transparent multiplicative return and forecast-error attribution."""
from __future__ import annotations

from dataclasses import dataclass
from math import exp, isfinite, log
from typing import Mapping


@dataclass(frozen=True)
class ReturnAttributionInput:
    operating_metric_start: float
    operating_metric_end: float
    valuation_multiple_start: float
    valuation_multiple_end: float
    dividend_reinvestment_factor: float = 1.0
    fx_factor: float = 1.0
    other_per_share_factor: float = 1.0

    def validate(self) -> None:
        values = (
            self.operating_metric_start,
            self.operating_metric_end,
            self.valuation_multiple_start,
            self.valuation_multiple_end,
            self.dividend_reinvestment_factor,
            self.fx_factor,
            self.other_per_share_factor,
        )
        if not all(isfinite(value) and value > 0 for value in values):
            raise ValueError("all attribution values/factors must be positive and finite")


@dataclass(frozen=True)
class ReturnAttributionResult:
    factors: Mapping[str, float]
    log_contributions: Mapping[str, float]
    contribution_shares: Mapping[str, float]
    total_factor: float
    total_return: float

    def reconstructed_factor(self) -> float:
        value = 1.0
        for factor in self.factors.values():
            value *= factor
        return value


def attribute_total_return(
    inputs: ReturnAttributionInput,
) -> ReturnAttributionResult:
    inputs.validate()
    factors = {
        "operating_metric_growth": (
            inputs.operating_metric_end / inputs.operating_metric_start
        ),
        "valuation_multiple_change": (
            inputs.valuation_multiple_end / inputs.valuation_multiple_start
        ),
        "dividend_reinvestment": inputs.dividend_reinvestment_factor,
        "fx_change": inputs.fx_factor,
        "other_per_share_change": inputs.other_per_share_factor,
    }
    log_contributions = {name: log(value) for name, value in factors.items()}
    total_log_return = sum(log_contributions.values())
    total_factor = exp(total_log_return)
    if abs(total_log_return) < 1e-15:
        shares = {name: 0.0 for name in factors}
    else:
        shares = {
            name: contribution / total_log_return
            for name, contribution in log_contributions.items()
        }
    return ReturnAttributionResult(
        factors=factors,
        log_contributions=log_contributions,
        contribution_shares=shares,
        total_factor=total_factor,
        total_return=total_factor - 1.0,
    )


@dataclass(frozen=True)
class ForecastError:
    metric: str
    forecast: float
    actual: float
    unit: str | None = None

    @property
    def absolute_error(self) -> float:
        return self.actual - self.forecast

    @property
    def relative_error(self) -> float | None:
        if self.forecast == 0:
            return None
        return self.actual / self.forecast - 1.0


def forecast_error_table(
    forecasts: Mapping[str, tuple[float, str | None]],
    actuals: Mapping[str, tuple[float, str | None]],
) -> tuple[ForecastError, ...]:
    if forecasts.keys() != actuals.keys():
        missing_forecast = sorted(actuals.keys() - forecasts.keys())
        missing_actual = sorted(forecasts.keys() - actuals.keys())
        raise ValueError(
            "forecast and actual metrics differ: "
            f"missing_forecast={missing_forecast}, missing_actual={missing_actual}"
        )
    rows: list[ForecastError] = []
    for metric in sorted(forecasts):
        forecast_value, forecast_unit = forecasts[metric]
        actual_value, actual_unit = actuals[metric]
        if forecast_unit != actual_unit:
            raise ValueError(f"unit mismatch for {metric}")
        if not isfinite(forecast_value) or not isfinite(actual_value):
            raise ValueError(f"non-finite forecast/actual for {metric}")
        rows.append(
            ForecastError(
                metric=metric,
                forecast=forecast_value,
                actual=actual_value,
                unit=forecast_unit,
            )
        )
    return tuple(rows)
