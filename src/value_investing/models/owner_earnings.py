"""Deterministic Owner Earnings DCF used by the Gate-0 replay.

Forward valuation and Reverse DCF intentionally share the same forecast and
terminal-value functions. Database access, market-data access and investment
decisions do not belong in this module.
"""

from __future__ import annotations

from dataclasses import dataclass
from math import isfinite
from typing import Iterable, Sequence


@dataclass(frozen=True, slots=True)
class OwnerEarningsScenario:
    name: str
    probability: float
    stage1_growth: float
    discount_rate: float
    terminal_growth: float
    forecast_horizon_years: int = 10
    stage1_years: int = 5
    required_return_hurdle: float = 0.15

    def validate(self) -> None:
        if not self.name.strip():
            raise ValueError("scenario name must not be empty")
        numeric = (
            self.probability,
            self.stage1_growth,
            self.discount_rate,
            self.terminal_growth,
            self.required_return_hurdle,
        )
        if not all(isfinite(value) for value in numeric):
            raise ValueError("scenario inputs must be finite")
        if self.probability < 0:
            raise ValueError("probability must be non-negative")
        if self.stage1_growth <= -1 or self.terminal_growth <= -1:
            raise ValueError("growth rates must be greater than -100%")
        if self.discount_rate <= self.terminal_growth:
            raise ValueError("discount_rate must exceed terminal_growth")
        if self.required_return_hurdle <= self.terminal_growth:
            raise ValueError("required_return_hurdle must exceed terminal_growth")
        if self.forecast_horizon_years < 1:
            raise ValueError("forecast_horizon_years must be positive")
        if not 1 <= self.stage1_years <= self.forecast_horizon_years:
            raise ValueError("stage1_years must be within the forecast horizon")


@dataclass(frozen=True, slots=True)
class ForecastPoint:
    year: int
    growth_rate: float
    owner_earnings: float


@dataclass(frozen=True, slots=True)
class ScenarioValuation:
    scenario: str
    probability: float
    forecast: tuple[ForecastPoint, ...]
    pv_explicit_period: float
    pv_terminal: float
    equity_value: float
    intrinsic_value_per_share: float
    terminal_value_share: float
    hurdle_value: float
    hurdle_value_per_share: float


@dataclass(frozen=True, slots=True)
class ScenarioSetValuation:
    scenarios: tuple[ScenarioValuation, ...]
    weighted_intrinsic_value_per_share: float
    weighted_hurdle_value_per_share: float
    weighted_terminal_value_share: float


@dataclass(frozen=True, slots=True)
class ReverseDCFResult:
    target_price: float
    implied_stage1_growth: float | None
    residual: float | None
    iterations: int
    converged: bool
    lower_bound: float
    upper_bound: float


def _require_positive(name: str, value: float) -> None:
    if not isfinite(value) or value <= 0:
        raise ValueError(f"{name} must be a positive finite number")


def forecast_owner_earnings(
    base_owner_earnings: float,
    scenario: OwnerEarningsScenario,
) -> tuple[ForecastPoint, ...]:
    """Forecast owner earnings with a linear fade to terminal growth."""

    _require_positive("base_owner_earnings", base_owner_earnings)
    scenario.validate()

    current = float(base_owner_earnings)
    points: list[ForecastPoint] = []
    fade_years = scenario.forecast_horizon_years - scenario.stage1_years

    for year in range(1, scenario.forecast_horizon_years + 1):
        if year <= scenario.stage1_years or fade_years == 0:
            growth = scenario.stage1_growth
        else:
            fade_position = (year - scenario.stage1_years) / fade_years
            growth = scenario.stage1_growth + (
                scenario.terminal_growth - scenario.stage1_growth
            ) * fade_position
        current *= 1.0 + growth
        points.append(ForecastPoint(year, growth, current))

    return tuple(points)


def _value_cash_flows(
    forecast: Sequence[ForecastPoint],
    discount_rate: float,
    terminal_growth: float,
) -> tuple[float, float, float]:
    if discount_rate <= terminal_growth:
        raise ValueError("discount_rate must exceed terminal_growth")
    if not forecast:
        raise ValueError("forecast must not be empty")

    explicit = sum(
        point.owner_earnings / (1.0 + discount_rate) ** point.year
        for point in forecast
    )
    last = forecast[-1]
    terminal_at_horizon = (
        last.owner_earnings
        * (1.0 + terminal_growth)
        / (discount_rate - terminal_growth)
    )
    terminal_pv = terminal_at_horizon / (1.0 + discount_rate) ** last.year
    return explicit, terminal_pv, explicit + terminal_pv


def value_owner_earnings_scenario(
    base_owner_earnings: float,
    shares_outstanding: float,
    scenario: OwnerEarningsScenario,
) -> ScenarioValuation:
    """Value one scenario and calculate the separate 15% hurdle price."""

    _require_positive("shares_outstanding", shares_outstanding)
    forecast = forecast_owner_earnings(base_owner_earnings, scenario)
    explicit, terminal, equity_value = _value_cash_flows(
        forecast, scenario.discount_rate, scenario.terminal_growth
    )
    _, _, hurdle_value = _value_cash_flows(
        forecast, scenario.required_return_hurdle, scenario.terminal_growth
    )
    return ScenarioValuation(
        scenario=scenario.name,
        probability=scenario.probability,
        forecast=forecast,
        pv_explicit_period=explicit,
        pv_terminal=terminal,
        equity_value=equity_value,
        intrinsic_value_per_share=equity_value / shares_outstanding,
        terminal_value_share=terminal / equity_value,
        hurdle_value=hurdle_value,
        hurdle_value_per_share=hurdle_value / shares_outstanding,
    )


def value_owner_earnings_scenarios(
    base_owner_earnings: float,
    shares_outstanding: float,
    scenarios: Iterable[OwnerEarningsScenario],
) -> ScenarioSetValuation:
    """Value an auditable scenario set and calculate weighted summaries."""

    scenario_list = tuple(scenarios)
    if not scenario_list:
        raise ValueError("at least one scenario is required")
    values = tuple(
        value_owner_earnings_scenario(base_owner_earnings, shares_outstanding, item)
        for item in scenario_list
    )
    total_probability = sum(value.probability for value in values)
    if total_probability <= 0:
        raise ValueError("scenario probabilities must sum to a positive value")

    def weighted(attribute: str) -> float:
        return sum(
            getattr(value, attribute) * value.probability for value in values
        ) / total_probability

    return ScenarioSetValuation(
        scenarios=values,
        weighted_intrinsic_value_per_share=weighted("intrinsic_value_per_share"),
        weighted_hurdle_value_per_share=weighted("hurdle_value_per_share"),
        weighted_terminal_value_share=weighted("terminal_value_share"),
    )


def solve_implied_stage1_growth(
    *,
    target_price: float,
    base_owner_earnings: float,
    shares_outstanding: float,
    scenario_template: OwnerEarningsScenario,
    lower_bound: float = -0.20,
    upper_bound: float = 0.40,
    tolerance: float = 1e-8,
    max_iterations: int = 200,
) -> ReverseDCFResult:
    """Solve market-implied stage-1 growth with the forward DCF function.

    A non-converged result is returned when the target price is outside the
    economic range spanned by the supplied bounds; no nearest-grid value is
    silently substituted.
    """

    _require_positive("target_price", target_price)
    _require_positive("base_owner_earnings", base_owner_earnings)
    _require_positive("shares_outstanding", shares_outstanding)
    if lower_bound >= upper_bound:
        raise ValueError("lower_bound must be less than upper_bound")
    if tolerance <= 0 or max_iterations < 1:
        raise ValueError("invalid solver controls")

    def residual(growth: float) -> float:
        scenario = OwnerEarningsScenario(
            name=scenario_template.name,
            probability=scenario_template.probability,
            stage1_growth=growth,
            discount_rate=scenario_template.discount_rate,
            terminal_growth=scenario_template.terminal_growth,
            forecast_horizon_years=scenario_template.forecast_horizon_years,
            stage1_years=scenario_template.stage1_years,
            required_return_hurdle=scenario_template.required_return_hurdle,
        )
        valuation = value_owner_earnings_scenario(
            base_owner_earnings, shares_outstanding, scenario
        )
        return valuation.intrinsic_value_per_share - target_price

    low, high = float(lower_bound), float(upper_bound)
    low_residual, high_residual = residual(low), residual(high)
    if low_residual == 0:
        return ReverseDCFResult(target_price, low, 0.0, 0, True, low, high)
    if high_residual == 0:
        return ReverseDCFResult(target_price, high, 0.0, 0, True, low, high)
    if low_residual * high_residual > 0:
        return ReverseDCFResult(
            target_price, None, None, 0, False, lower_bound, upper_bound
        )

    midpoint = low
    midpoint_residual = low_residual
    for iteration in range(1, max_iterations + 1):
        midpoint = (low + high) / 2.0
        midpoint_residual = residual(midpoint)
        if abs(midpoint_residual) <= tolerance or (high - low) / 2.0 <= tolerance:
            return ReverseDCFResult(
                target_price,
                midpoint,
                midpoint_residual,
                iteration,
                True,
                lower_bound,
                upper_bound,
            )
        if low_residual * midpoint_residual <= 0:
            high, high_residual = midpoint, midpoint_residual
        else:
            low, low_residual = midpoint, midpoint_residual

    return ReverseDCFResult(
        target_price,
        midpoint,
        midpoint_residual,
        max_iterations,
        False,
        lower_bound,
        upper_bound,
    )
