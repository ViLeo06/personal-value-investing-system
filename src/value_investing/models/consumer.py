from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

from value_investing.valuation.core import DcfResult, dcf_from_cash_flows


@dataclass(frozen=True, slots=True)
class ConsumerDriverYear:
    volume_growth: float
    price_mix_growth: float
    operating_margin: float
    cash_tax_rate: float
    ronic: float


@dataclass(frozen=True, slots=True)
class ConsumerForecastYear:
    year: int
    revenue: float
    nopat: float
    incremental_nopat: float
    reinvestment: float
    free_cash_flow: float
    ronic: float


@dataclass(frozen=True, slots=True)
class ConsumerValuation:
    forecast: tuple[ConsumerForecastYear, ...]
    dcf: DcfResult
    terminal_reinvestment_rate: float


def forecast_consumer(
    *,
    base_revenue: float,
    base_operating_margin: float,
    base_cash_tax_rate: float,
    drivers: Sequence[ConsumerDriverYear],
) -> tuple[ConsumerForecastYear, ...]:
    if base_revenue <= 0:
        raise ValueError("base_revenue must be positive")
    if not drivers:
        raise ValueError("drivers cannot be empty")
    previous_revenue = base_revenue
    previous_nopat = base_revenue * base_operating_margin * (1.0 - base_cash_tax_rate)
    output: list[ConsumerForecastYear] = []
    for year, driver in enumerate(drivers, 1):
        if not 0 <= driver.operating_margin <= 1:
            raise ValueError("operating_margin must be between 0 and 1")
        if not 0 <= driver.cash_tax_rate <= 1:
            raise ValueError("cash_tax_rate must be between 0 and 1")
        if driver.ronic <= 0:
            raise ValueError("ronic must be positive")
        revenue_growth = (1.0 + driver.volume_growth) * (1.0 + driver.price_mix_growth) - 1.0
        revenue = previous_revenue * (1.0 + revenue_growth)
        nopat = revenue * driver.operating_margin * (1.0 - driver.cash_tax_rate)
        incremental_nopat = nopat - previous_nopat
        reinvestment = incremental_nopat / driver.ronic
        free_cash_flow = nopat - reinvestment
        output.append(
            ConsumerForecastYear(
                year=year,
                revenue=revenue,
                nopat=nopat,
                incremental_nopat=incremental_nopat,
                reinvestment=reinvestment,
                free_cash_flow=free_cash_flow,
                ronic=driver.ronic,
            )
        )
        previous_revenue = revenue
        previous_nopat = nopat
    return tuple(output)


def value_consumer(
    *,
    base_revenue: float,
    base_operating_margin: float,
    base_cash_tax_rate: float,
    drivers: Sequence[ConsumerDriverYear],
    discount_rate: float,
    terminal_growth: float,
    terminal_ronic: float,
) -> ConsumerValuation:
    if terminal_ronic <= terminal_growth:
        raise ValueError("terminal_ronic must exceed terminal_growth")
    forecast = forecast_consumer(
        base_revenue=base_revenue,
        base_operating_margin=base_operating_margin,
        base_cash_tax_rate=base_cash_tax_rate,
        drivers=drivers,
    )
    terminal_reinvestment_rate = terminal_growth / terminal_ronic
    terminal_nopat = forecast[-1].nopat
    terminal_cash_flow = terminal_nopat * (1.0 - terminal_reinvestment_rate)
    dcf = dcf_from_cash_flows(
        [year.free_cash_flow for year in forecast],
        discount_rate=discount_rate,
        terminal_growth=terminal_growth,
        terminal_cash_flow=terminal_cash_flow,
    )
    return ConsumerValuation(
        forecast=forecast,
        dcf=dcf,
        terminal_reinvestment_rate=terminal_reinvestment_rate,
    )
