import pytest

from value_investing.execution import (
    CostSchedule,
    PositionState,
    TradingTerms,
    affordable_buy_quantity,
    estimate_execution_costs,
    execute_trade,
    round_buy_quantity,
)


def test_a_share_buy_rounds_down_to_board_lot():
    terms = TradingTerms(board_lot=100)
    assert round_buy_quantity(349, terms) == 300


def test_commission_tax_and_transfer_fee_are_explicit():
    schedule = CostSchedule(
        sell_commission_rate=0.0003,
        minimum_commission=5.0,
        sell_tax_rate=0.001,
        transfer_fee_rate=0.00001,
    )
    costs = estimate_execution_costs("sell", 100, 100.0, schedule)
    assert costs.commission == pytest.approx(5.0)
    assert costs.tax == pytest.approx(10.0)
    assert costs.transfer_fee == pytest.approx(0.1)
    assert costs.total == pytest.approx(15.1)


def test_buy_and_sell_update_cash_and_quantity():
    terms = TradingTerms(board_lot=100)
    schedule = CostSchedule(
        buy_commission_rate=0.0003,
        sell_commission_rate=0.0003,
        minimum_commission=5.0,
        sell_tax_rate=0.001,
    )
    bought = execute_trade(
        PositionState(cash=100_000.0, quantity=0),
        side="buy",
        requested_quantity=350,
        price=100.0,
        terms=terms,
        schedule=schedule,
    )
    assert bought.quantity == 300
    assert bought.resulting_state.quantity == 300
    assert bought.resulting_state.cash == pytest.approx(69_991.0)

    sold = execute_trade(
        bought.resulting_state,
        side="sell",
        requested_quantity=300,
        price=110.0,
        terms=terms,
        schedule=schedule,
    )
    assert sold.resulting_state.quantity == 0
    assert sold.resulting_state.cash == pytest.approx(102_948.1)


def test_affordable_quantity_includes_minimum_commission():
    quantity = affordable_buy_quantity(
        10_000.0,
        100.0,
        TradingTerms(board_lot=100),
        CostSchedule(buy_commission_rate=0.0003, minimum_commission=5.0),
    )
    assert quantity == 0


def test_sell_cannot_exceed_position():
    with pytest.raises(ValueError, match="more than"):
        execute_trade(
            PositionState(cash=0.0, quantity=50.0),
            side="sell",
            requested_quantity=51.0,
            price=10.0,
            terms=TradingTerms(board_lot=1),
            schedule=CostSchedule(),
        )
