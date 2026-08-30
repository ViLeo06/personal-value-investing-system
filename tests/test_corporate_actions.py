from datetime import date, datetime, timezone

import pytest

from value_investing.corporate_actions import (
    CorporateActionEvent,
    ReinvestmentInstruction,
    ShareholderState,
    apply_corporate_actions,
    terminal_shareholder_value,
)


def _known(action_id, action_type, effective_date, **kwargs):
    return CorporateActionEvent(
        action_id=action_id,
        action_type=action_type,
        effective_date=effective_date,
        available_at=datetime(2021, 1, 1, tzinfo=timezone.utc),
        **kwargs,
    )


def test_cash_dividend_reinvestment_and_split():
    result = apply_corporate_actions(
        ShareholderState(quantity=100.0, cash=0.0),
        [
            _known(
                "dividend",
                "cash_dividend",
                date(2022, 6, 1),
                cash_amount_per_share=2.0,
                currency="CNY",
            ),
            _known(
                "split",
                "split",
                date(2023, 1, 1),
                ratio_numerator=2.0,
                ratio_denominator=1.0,
            ),
        ],
        decision_at=datetime(2021, 8, 30, tzinfo=timezone.utc),
        reinvestments=[ReinvestmentInstruction("dividend", price=100.0)],
    )
    assert result.entries[0].quantity_change == pytest.approx(2.0)
    assert result.final_state.quantity == pytest.approx(204.0)
    assert result.final_state.cash == pytest.approx(0.0)
    assert terminal_shareholder_value(result.final_state, 50.0) == pytest.approx(10_200.0)


def test_rights_issue_uses_available_cash_and_participation():
    result = apply_corporate_actions(
        ShareholderState(quantity=100.0, cash=1_000.0),
        [
            _known(
                "rights",
                "rights_issue",
                date(2022, 1, 1),
                ratio_numerator=1.0,
                ratio_denominator=10.0,
                subscription_price=20.0,
            )
        ],
        decision_at=datetime(2021, 8, 30, tzinfo=timezone.utc),
        reinvestments=[
            ReinvestmentInstruction("rights", price=20.0, participation_rate=0.5)
        ],
    )
    assert result.final_state.quantity == pytest.approx(105.0)
    assert result.final_state.cash == pytest.approx(900.0)


def test_unknown_at_decision_effective_action_is_rejected():
    event = CorporateActionEvent(
        action_id="future_knowledge",
        action_type="cash_dividend",
        effective_date=date(2021, 8, 1),
        available_at=datetime(2021, 9, 1, tzinfo=timezone.utc),
        cash_amount_per_share=1.0,
    )
    with pytest.raises(ValueError, match="PIT leakage"):
        apply_corporate_actions(
            ShareholderState(quantity=1.0),
            [event],
            decision_at=datetime(2021, 8, 30, tzinfo=timezone.utc),
        )


def test_insufficient_cash_for_rights_is_rejected():
    with pytest.raises(ValueError, match="insufficient cash"):
        apply_corporate_actions(
            ShareholderState(quantity=100.0, cash=0.0),
            [
                _known(
                    "rights",
                    "rights_issue",
                    date(2022, 1, 1),
                    ratio_numerator=1.0,
                    ratio_denominator=1.0,
                    subscription_price=10.0,
                )
            ],
            decision_at=datetime(2021, 8, 30, tzinfo=timezone.utc),
            reinvestments=[
                ReinvestmentInstruction("rights", price=10.0, participation_rate=1.0)
            ],
        )
