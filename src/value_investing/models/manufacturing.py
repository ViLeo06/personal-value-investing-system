from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

from value_investing.valuation.core import DcfResult, dcf_from_cash_flows


@dataclass(frozen=True, slots=True)
class ManufacturingDriverYear:
    units: float
    average_price: float
    variable_cost_per_unit: float
    fixed_operating_cost: float
    depreciation: float
    capital_expenditure: float
    working_capital_percent_revenue: float
    cash_tax_rate: float


@dataclass(frozen=True, slots=True)
class ManufacturingForecastYear:
    year: int
    revenue: float
    ebit: float
    nopat: float
    change_working_capital: float
    net_investment: float
    free_cash_flow: float
    ronic: float | None


def forecast_manufacturing(
    *,
    base_revenue: float,
    base_nopat: float,
    base_working_capital: float,
    drivers: Sequence[ManufacturingDriverYear],
) -> tuple[ManufacturingForecastYear, ...]:
    if not drivers:
        raise ValueError("drivers cannot be empty")
    previous_nopat = base_nopat
    previous_working_capital = base_working_capital
    output: list[ManufacturingForecastYear] = []
    for year, driver in enumerate(drivers, 1):
        if driver.units < 0 or driver.average_price < 0:
            raise ValueError("units and average_price cannot be negative")
        if not 0 <= driver.cash_tax_rate <= 1:
            raise ValueError("cash_tax_rate must be between 0 and 1")
        revenue = driver.units * driver.average_price
        ebit = (
            revenue
            - driver.units * driver.variable_cost_per_unit
            - driver.fixed_operating_cost
            - driver.depreciation
        )
        nopat = ebit * (1.0 - driver.cash_tax_rate)
        working_capital = revenue * driver.working_capital_percent_revenue
        change_working_capital = working_capital - previous_working_capital
        net_investment = driver.capital_expenditure - driver.depreciation + change_working_capital
        free_cash_flow = (
            nopat
            + driver.depreciation
            - driver.capital_expenditure
            - change_working_capital
        )
        incremental_nopat = nopat - previous_nopat
        ronic = None if net_investment <= 0 else incremental_nopat / net_investment
        output.append(
            ManufacturingForecastYear(
                year=year,
                revenue=revenue,
                ebit=ebit,
                nopat=nopat,
                change_working_capital=change_working_capital,
                net_investment=net_investment,
                free_cash_flow=free_cash_flow,
                ronic=ronic,
            )
        )
        previous_nopat = nopat
        previous_working_capital = working_capital
    return tuple(output)


def value_manufacturing(
    *,
    base_revenue: float,
    base_nopat: float,
    base_working_capital: float,
    drivers: Sequence[ManufacturingDriverYear],
    discount_rate: float,
    terminal_growth: float,
) -> tuple[tuple[ManufacturingForecastYear, ...], DcfResult]:
    forecast = forecast_manufacturing(
        base_revenue=base_revenue,
        base_nopat=base_nopat,
        base_working_capital=base_working_capital,
        drivers=drivers,
    )
    dcf = dcf_from_cash_flows(
        [year.free_cash_flow for year in forecast],
        discount_rate=discount_rate,
        terminal_growth=terminal_growth,
    )
    return forecast, dcf
