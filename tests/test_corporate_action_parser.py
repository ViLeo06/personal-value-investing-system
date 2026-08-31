from datetime import datetime, timezone
from decimal import Decimal

import pytest

from value_investing.data.corporate_actions import (
    CorporateActionParseError,
    DividendFieldMap,
    eastmoney_cash_dividend_map,
    parse_cash_dividend,
)


def test_per_ten_share_dividend_is_normalized_per_share() -> None:
    action = parse_cash_dividend(
        {
            "PRETAX_BONUS_RMB": "216.75",
            "EX_DIVIDEND_DATE": "2023-06-30 00:00:00",
            "EQUITY_RECORD_DATE": "2023-06-29",
            "CASH_DIVIDEND_DATE": "2023-06-30",
            "NOTICE_DATE": "2023-06-20",
        },
        security_code="600519.SH",
        available_at=datetime(2023, 6, 21, tzinfo=timezone.utc),
        field_map=eastmoney_cash_dividend_map(),
        evidence_grade=1,
    )
    assert action.cash_amount_per_share == Decimal("21.675")
    assert action.ex_date.isoformat() == "2023-06-30"
    assert action.record_date.isoformat() == "2023-06-29"
    assert len(action.record_hash or "") == 64


def test_custom_field_map_is_provider_neutral() -> None:
    field_map = DividendFieldMap(
        cash_amount_fields=("cash",),
        ex_date_fields=("ex",),
        cash_unit="per_share",
        currency="HKD",
    )
    action = parse_cash_dividend(
        {"cash": "2.50", "ex": "2024-05-02"},
        security_code="0700.HK",
        available_at=datetime(2024, 4, 1, tzinfo=timezone.utc),
        field_map=field_map,
        evidence_grade=2,
    )
    assert action.cash_amount_per_share == Decimal("2.50")
    assert action.currency == "HKD"


def test_missing_ex_date_is_rejected() -> None:
    with pytest.raises(CorporateActionParseError, match="Missing required date"):
        parse_cash_dividend(
            {"PRETAX_BONUS_RMB": "100"},
            security_code="600519.SH",
            available_at=datetime(2023, 1, 1, tzinfo=timezone.utc),
            field_map=eastmoney_cash_dividend_map(),
        )


def test_payment_before_ex_date_is_rejected() -> None:
    with pytest.raises(CorporateActionParseError, match="payment_date"):
        parse_cash_dividend(
            {
                "PRETAX_BONUS_RMB": "100",
                "EX_DIVIDEND_DATE": "2024-06-10",
                "PAYMENT_DATE": "2024-06-01",
            },
            security_code="600519.SH",
            available_at=datetime(2024, 5, 1, tzinfo=timezone.utc),
            field_map=eastmoney_cash_dividend_map(),
        )
