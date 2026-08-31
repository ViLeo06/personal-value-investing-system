from __future__ import annotations

from dataclasses import dataclass
from math import isfinite
from typing import Callable, Mapping, Sequence


class DataSufficiencyError(ValueError):
    def __init__(self, missing: Sequence[str]) -> None:
        self.missing = tuple(sorted(set(missing)))
        super().__init__("Missing required valuation inputs: " + ", ".join(self.missing))


@dataclass(frozen=True, slots=True)
class OwnerEarningsInputs:
    net_income_parent: float
    depreciation_amortization: float
    other_non_cash_adjustments: float
    maintenance_capex: float
    change_working_capital: float


@dataclass(frozen=True, slots=True)
class Scenario:
    name: str
    initial_growth: float
    explicit_years: int
    fade_years: int
    terminal_growth: float
    discount_rate: float
    shares_outstanding: float
    net_cash: float = 0.0


@dataclass(frozen=True, slots=True)
class ValuationResult:
    scenario: str
    enterprise_value: float
    equity_value: float
    value_per_share: float
    terminal_value_share: float
    owner_earnings_path: tuple[float, ...]
    growth_path: tuple[float, ...]


REQUIRED_METRICS = (
    "net_income_parent",
    "depreciation_amortization",
    "other_non_cash_adjustments",
    "maintenance_capex",
    "change_working_capital",
    "shares_outstanding",
    "net_cash",
)


def validate_required_metrics(metrics: Mapping[str, float]) -> None:
    missing = [name for name in REQUIRED_METRICS if name not in metrics]
    if missing:
        raise DataSufficiencyError(missing)
    bad = [name for name in REQUIRED_METRICS if not isfinite(float(metrics[name]))]
    if bad:
        raise ValueError("Non-finite valuation inputs: " + ", ".join(sorted(bad)))


def compute_owner_earnings(inputs: OwnerEarningsInputs) -> float:
    """Compute owner earnings under an explicit bridge.

    Positive change_working_capital means a cash use and is deducted.
    maintenance_capex must exclude growth capex.
    """
    result = (
        inputs.net_income_parent
        + inputs.depreciation_amortization
        + inputs.other_non_cash_adjustments
        - inputs.maintenance_capex
        - inputs.change_working_capital
    )
    if not isfinite(result):
        raise ValueError("Owner earnings must be finite")
    return result


def _growth_path(scenario: Scenario) -> tuple[float, ...]:
    if scenario.explicit_years < 1:
        raise ValueError("explicit_years must be positive")
    if scenario.fade_years < 0:
        raise ValueError("fade_years cannot be negative")
    if scenario.discount_rate <= scenario.terminal_growth:
        raise ValueError("discount_rate must be greater than terminal_growth")
    if scenario.shares_outstanding <= 0:
        raise ValueError("shares_outstanding must be positive")

    growth = [scenario.initial_growth] * scenario.explicit_years
    if scenario.fade_years:
        step = (scenario.initial_growth - scenario.terminal_growth) / scenario.fade_years
        growth.extend(
            scenario.initial_growth - step * year
            for year in range(1, scenario.fade_years + 1)
        )
    return tuple(growth)


def discounted_owner_earnings_value(
    base_owner_earnings: float, scenario: Scenario
) -> ValuationResult:
    if base_owner_earnings <= 0:
        raise ValueError("base_owner_earnings must be positive")
    growth_path = _growth_path(scenario)
    cash_flows: list[float] = []
    current = base_owner_earnings
    for growth in growth_path:
        current *= 1.0 + growth
        cash_flows.append(current)

    r = scenario.discount_rate
    pv_explicit = sum(cf / ((1.0 + r) ** year) for year, cf in enumerate(cash_flows, 1))
    terminal_cf = cash_flows[-1] * (1.0 + scenario.terminal_growth)
    terminal_value = terminal_cf / (r - scenario.terminal_growth)
    pv_terminal = terminal_value / ((1.0 + r) ** len(cash_flows))
    enterprise_value = pv_explicit + pv_terminal
    equity_value = enterprise_value + scenario.net_cash
    value_per_share = equity_value / scenario.shares_outstanding
    terminal_share = pv_terminal / enterprise_value
    return ValuationResult(
        scenario=scenario.name,
        enterprise_value=enterprise_value,
        equity_value=equity_value,
        value_per_share=value_per_share,
        terminal_value_share=terminal_share,
        owner_earnings_path=tuple(cash_flows),
        growth_path=growth_path,
    )


def _bisect(
    function: Callable[[float], float],
    lower: float,
    upper: float,
    tolerance: float = 1e-10,
    max_iterations: int = 250,
) -> float:
    f_lower = function(lower)
    f_upper = function(upper)
    if f_lower == 0:
        return lower
    if f_upper == 0:
        return upper
    if f_lower * f_upper > 0:
        raise ValueError("Root is not bracketed")
    for _ in range(max_iterations):
        mid = (lower + upper) / 2.0
        f_mid = function(mid)
        if abs(f_mid) <= tolerance or (upper - lower) / 2.0 <= tolerance:
            return mid
        if f_lower * f_mid <= 0:
            upper = mid
        else:
            lower = mid
            f_lower = f_mid
    raise RuntimeError("Bisection did not converge")


def implied_initial_growth(
    target_price: float,
    base_owner_earnings: float,
    scenario_template: Scenario,
    lower: float = -0.25,
    upper: float = 0.40,
) -> float:
    """Reverse DCF using the exact same forward valuation function."""
    if target_price <= 0:
        raise ValueError("target_price must be positive")

    def residual(growth: float) -> float:
        scenario = Scenario(
            name=scenario_template.name,
            initial_growth=growth,
            explicit_years=scenario_template.explicit_years,
            fade_years=scenario_template.fade_years,
            terminal_growth=scenario_template.terminal_growth,
            discount_rate=scenario_template.discount_rate,
            shares_outstanding=scenario_template.shares_outstanding,
            net_cash=scenario_template.net_cash,
        )
        return discounted_owner_earnings_value(base_owner_earnings, scenario).value_per_share - target_price

    return _bisect(residual, lower, upper)


def maximum_entry_price(
    future_sale_price: float,
    annual_dividends: Sequence[float],
    hurdle_rate: float = 0.15,
) -> float:
    """Present value of dividends and exit price at the investor hurdle rate."""
    if future_sale_price < 0:
        raise ValueError("future_sale_price cannot be negative")
    if hurdle_rate <= -1:
        raise ValueError("hurdle_rate must be greater than -100%")
    pv_dividends = sum(
        dividend / ((1.0 + hurdle_rate) ** year)
        for year, dividend in enumerate(annual_dividends, 1)
    )
    horizon = len(annual_dividends)
    pv_exit = future_sale_price / ((1.0 + hurdle_rate) ** horizon)
    return pv_dividends + pv_exit
