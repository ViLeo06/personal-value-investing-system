from datetime import date

import pytest

from value_investing.backtest.costs import CostComponent, calculate_transaction_cost


def components():
    return [
        CostComponent(
            "equity_v1", "XSHG", "equity", "both", "commission",
            date(2000, 1, 1), None, 0.0003, 5.0
        ),
        CostComponent(
            "equity_v1", "XSHG", "equity", "both", "transfer_fee",
            date(2008, 9, 19), date(2022, 4, 28), 0.00002
        ),
        CostComponent(
            "equity_v1", "XSHG", "equity", "both", "transfer_fee",
            date(2022, 4, 29), None, 0.00001
        ),
        CostComponent(
            "equity_v1", "XSHG", "equity", "sell", "stamp_duty",
            date(2008, 9, 19), date(2023, 8, 27), 0.001
        ),
        CostComponent(
            "equity_v1", "XSHG", "equity", "sell", "stamp_duty",
            date(2023, 8, 28), None, 0.0005
        ),
    ]


def test_buy_fee_uses_each_component_independently():
    total, detail = calculate_transaction_cost(
        components(), policy_version="equity_v1", market_code="XSHG",
        security_type="equity", side="buy", trade_date=date(2021, 4, 1),
        notional=10_000,
    )
    assert detail["commission"] == pytest.approx(5.0)
    assert detail["transfer_fee"] == pytest.approx(0.2)
    assert total == pytest.approx(5.2)


def test_sell_fee_uses_date_effective_stamp_and_transfer_rates():
    total, detail = calculate_transaction_cost(
        components(), policy_version="equity_v1", market_code="XSHG",
        security_type="equity", side="sell", trade_date=date(2026, 4, 1),
        notional=100_000,
    )
    assert detail["commission"] == pytest.approx(30.0)
    assert detail["transfer_fee"] == pytest.approx(1.0)
    assert detail["stamp_duty"] == pytest.approx(50.0)
    assert total == pytest.approx(81.0)


def test_rejects_missing_policy():
    with pytest.raises(ValueError, match="no cost components"):
        calculate_transaction_cost(
            components(), policy_version="missing", market_code="XSHG",
            security_type="equity", side="buy", trade_date=date(2021, 4, 1),
            notional=10_000,
        )
