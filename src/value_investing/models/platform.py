from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Sequence

from value_investing.valuation.core import DcfResult, dcf_from_cash_flows


@dataclass(frozen=True, slots=True)
class SegmentDriver:
    name: str
    base_revenue: float
    annual_growth: tuple[float, ...]
    operating_margin: tuple[float, ...]


@dataclass(frozen=True, slots=True)
class PlatformYear:
    year: int
    revenue: float
    ebit: float
    nopat: float
    free_cash_flow: float


@dataclass(frozen=True, slots=True)
class SotPPart:
    name: str
    gross_value: float
    ownership: float = 1.0
    haircut: float = 0.0

    @property
    def attributable_value(self) -> float:
        if not 0 <= self.ownership <= 1:
            raise ValueError("ownership must be between 0 and 1")
        if not 0 <= self.haircut < 1:
            raise ValueError("haircut must be between 0 and 1")
        return self.gross_value * self.ownership * (1.0 - self.haircut)


def forecast_platform(
    *,
    segments: Sequence[SegmentDriver],
    cash_tax_rate: float,
    reinvestment_rate: Sequence[float],
) -> tuple[PlatformYear, ...]:
    if not segments:
        raise ValueError("segments cannot be empty")
    horizon = len(reinvestment_rate)
    if horizon < 1:
        raise ValueError("reinvestment_rate cannot be empty")
    if not 0 <= cash_tax_rate <= 1:
        raise ValueError("cash_tax_rate must be between 0 and 1")
    for segment in segments:
        if len(segment.annual_growth) != horizon or len(segment.operating_margin) != horizon:
            raise ValueError("All segment driver paths must match the horizon")

    current_revenue = {segment.name: segment.base_revenue for segment in segments}
    output: list[PlatformYear] = []
    for index in range(horizon):
        total_revenue = 0.0
        total_ebit = 0.0
        for segment in segments:
            current_revenue[segment.name] *= 1.0 + segment.annual_growth[index]
            revenue = current_revenue[segment.name]
            margin = segment.operating_margin[index]
            if not -1 <= margin <= 1:
                raise ValueError("operating_margin must be between -1 and 1")
            total_revenue += revenue
            total_ebit += revenue * margin
        nopat = total_ebit * (1.0 - cash_tax_rate)
        free_cash_flow = nopat * (1.0 - reinvestment_rate[index])
        output.append(
            PlatformYear(
                year=index + 1,
                revenue=total_revenue,
                ebit=total_ebit,
                nopat=nopat,
                free_cash_flow=free_cash_flow,
            )
        )
    return tuple(output)


def value_platform_operations(
    *,
    forecast: Sequence[PlatformYear],
    discount_rate: float,
    terminal_growth: float,
) -> DcfResult:
    return dcf_from_cash_flows(
        [year.free_cash_flow for year in forecast],
        discount_rate=discount_rate,
        terminal_growth=terminal_growth,
    )


def sum_of_parts(parts: Iterable[SotPPart], net_debt: float = 0.0) -> float:
    return sum(part.attributable_value for part in parts) - net_debt
