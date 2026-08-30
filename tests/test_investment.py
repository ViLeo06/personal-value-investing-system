import pytest

from value_investing.investment import annualized_return, margin_of_safety, target_entry_price


def test_annualized_return_and_target_price_are_inverses():
    end_value = 2_000.0
    target = target_entry_price(end_value, 0.15, 5.0)
    assert annualized_return(target, end_value, 5.0) == pytest.approx(0.15)


def test_margin_of_safety():
    assert margin_of_safety(80.0, 100.0) == pytest.approx(0.20)


def test_zero_terminal_value_is_total_loss():
    assert annualized_return(100.0, 0.0, 5.0) == -1.0
