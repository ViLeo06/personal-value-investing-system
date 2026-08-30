import math

import pytest

from value_investing.valuation import bounded_bisection, dcf, gordon_terminal_value


def test_terminal_requires_wacc_above_growth():
    with pytest.raises(ValueError):
        gordon_terminal_value(100.0, 0.03, 0.03)


def test_dcf_components_reconcile():
    result = dcf([100.0, 110.0, 120.0], 0.10, 0.03)
    assert math.isclose(result.enterprise_value, result.pv_explicit_cash_flows + result.pv_terminal_value)


def test_bounded_solver_converges():
    result = bounded_bisection(lambda x: x * x - 4.0, 0.0, 3.0)
    assert result.converged
    assert result.value == pytest.approx(2.0, abs=1e-7)
    assert abs(result.residual or 0.0) < 1e-6


def test_bounded_solver_reports_no_bracket():
    result = bounded_bisection(lambda x: x * x + 1.0, -2.0, 2.0)
    assert not result.converged
    assert result.value is None
