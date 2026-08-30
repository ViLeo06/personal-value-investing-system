"""Frozen Gate-0 fixtures extracted from the V1.0 historical replay workbook.

These records are a migration bridge and golden-test source, not an authoritative
market-data feed. Every record must retain provenance to the legacy workbook.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from typing import Mapping

from .total_return import CorporateAction, TotalReturnResult, reconstruct_total_return


@dataclass(frozen=True)
class FrozenValuation:
    issuer_code: str
    security_code: str
    start_price: float
    end_price: float
    pessimistic_value: float
    base_value: float
    optimistic_value: float
    base_predicted_irr: float
    target_buy_price_15pct: float
    decision: str
    benchmark_cagr: float
    actions: tuple[CorporateAction, ...]
    reverse_dcf_summary: str


GATE0: Mapping[str, FrozenValuation] = {
    "KWEICHOW_MOUTAI": FrozenValuation(
        issuer_code="KWEICHOW_MOUTAI",
        security_code="600519.SH",
        start_price=1586.0,
        end_price=1297.4,
        pessimistic_value=737.77,
        base_value=1433.46,
        optimistic_value=2342.04,
        base_predicted_irr=0.0456,
        target_buy_price_15pct=1002.25,
        decision="wait",
        benchmark_cagr=0.0246,
        reverse_dcf_summary="implied first-five-year owner-earnings growth approximately 10.77%",
        actions=(
            CorporateAction(date(2022, 6, 30), "cash_dividend", 21.675, 2045.0, note="proxy reinvestment price"),
            CorporateAction(date(2022, 12, 30), "special_dividend", 21.91, 1742.06, note="proxy reinvestment price"),
            CorporateAction(date(2023, 6, 30), "cash_dividend", 25.911, 1691.0, note="proxy reinvestment price"),
            CorporateAction(date(2023, 12, 29), "special_dividend", 19.106, 1649.79, note="proxy reinvestment price"),
            CorporateAction(date(2024, 6, 28), "cash_dividend", 30.876, 1501.0, note="proxy reinvestment price"),
            CorporateAction(date(2024, 12, 31), "interim_dividend", 23.882, 1522.0, note="proxy reinvestment price"),
            CorporateAction(date(2025, 6, 30), "cash_dividend", 27.673, 1420.0, note="proxy reinvestment price"),
            CorporateAction(date(2025, 12, 31), "interim_dividend", 23.957, 1410.0, note="proxy reinvestment price"),
            CorporateAction(date(2026, 6, 30), "cash_dividend", 28.02423, 1168.63, note="proxy reinvestment price"),
        ),
    ),
    "TENCENT": FrozenValuation(
        issuer_code="TENCENT",
        security_code="0700.HK",
        start_price=465.8,
        end_price=455.2,
        pessimistic_value=338.14,
        base_value=588.31,
        optimistic_value=892.43,
        base_predicted_irr=0.1040,
        target_buy_price_15pct=380.30,
        decision="watch_wait",
        benchmark_cagr=0.0341,
        reverse_dcf_summary="legacy workbook market-implied core FCF path",
        actions=(
            CorporateAction(date(2022, 1, 31), "in_kind_distribution_equivalent", 13.4, 442.4, note="JD equivalent value proxy"),
            CorporateAction(date(2022, 5, 31), "cash_dividend", 1.6, 352.0),
            CorporateAction(date(2023, 1, 31), "in_kind_distribution_equivalent", 18.13, 342.87, note="Meituan equivalent value proxy"),
            CorporateAction(date(2023, 5, 31), "cash_dividend", 2.4, 335.0),
            CorporateAction(date(2024, 5, 31), "cash_dividend", 3.4, 397.0),
            CorporateAction(date(2025, 5, 30), "cash_dividend", 4.5, 510.0),
            CorporateAction(date(2026, 5, 29), "cash_dividend", 5.3, 460.2),
        ),
    ),
    "BYD": FrozenValuation(
        issuer_code="BYD",
        security_code="002594.SZ",
        start_price=281.97,
        end_price=92.32,
        pessimistic_value=0.0,
        base_value=22.78,
        optimistic_value=107.85,
        base_predicted_irr=-0.2127,
        target_buy_price_15pct=42.66,
        decision="avoid",
        benchmark_cagr=0.0246,
        reverse_dcf_summary="legacy workbook price implied normalized NOPAT above base case",
        actions=(
            CorporateAction(date(2022, 7, 29), "cash_dividend", 0.105, 329.0),
            CorporateAction(date(2023, 7, 28), "cash_dividend", 1.142, 259.0),
            CorporateAction(date(2024, 7, 31), "cash_dividend", 3.0977722, 243.0),
            CorporateAction(date(2025, 7, 31), "cash_dividend", 3.974, 350.0),
            CorporateAction(date(2025, 7, 31), "stock_dividend_and_capitalization", share_multiplier=3.0),
            CorporateAction(date(2026, 7, 31), "cash_dividend", 0.358, 95.77),
        ),
    ),
    "CMB": FrozenValuation(
        issuer_code="CMB",
        security_code="600036.SH",
        start_price=48.45,
        end_price=39.35,
        pessimistic_value=23.64,
        base_value=40.30,
        optimistic_value=61.57,
        base_predicted_irr=0.0578,
        target_buy_price_15pct=32.74,
        decision="wait",
        benchmark_cagr=0.0246,
        reverse_dcf_summary="legacy workbook current P/B implied long-run ROE",
        actions=(
            CorporateAction(date(2022, 7, 29), "cash_dividend", 1.522, 36.48),
            CorporateAction(date(2023, 7, 31), "cash_dividend", 1.738, 33.20),
            CorporateAction(date(2024, 7, 31), "cash_dividend", 1.972, 34.68),
            CorporateAction(date(2025, 7, 31), "cash_dividend", 2.000, 48.24),
            CorporateAction(date(2026, 1, 30), "interim_dividend", 1.013, 40.11),
            CorporateAction(date(2026, 7, 31), "cash_dividend", 1.003, 37.55),
        ),
    ),
}


def realized_results(years: float = 5.0) -> dict[str, TotalReturnResult]:
    return {
        code: reconstruct_total_return(
            start_price=fixture.start_price,
            end_price=fixture.end_price,
            actions=fixture.actions,
            years=years,
        )
        for code, fixture in GATE0.items()
    }


def decision_is_calibrated(predicted_irr: float, realized_cagr: float, hurdle: float = 0.15) -> bool:
    return (predicted_irr >= hurdle) == (realized_cagr >= hurdle)
