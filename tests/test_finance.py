import math
import unittest

from pvis.finance import irr, max_drawdown, npv, target_entry_price


class FinanceTests(unittest.TestCase):
    def test_irr_for_doubling_in_five_years(self) -> None:
        result = irr([-100.0, 0.0, 0.0, 0.0, 0.0, 200.0])
        self.assertAlmostEqual(result, math.pow(2.0, 1.0 / 5.0) - 1.0, places=9)

    def test_target_entry_price_matches_discounted_cash_flows(self) -> None:
        result = target_entry_price([0.0, 0.0, 0.0, 0.0, 0.0], 200.0, 0.15)
        self.assertAlmostEqual(result, 200.0 / (1.15**5), places=9)

    def test_max_drawdown(self) -> None:
        self.assertAlmostEqual(max_drawdown([100.0, 120.0, 90.0, 110.0]), -0.25)

    def test_invalid_cash_flow_rejected(self) -> None:
        with self.assertRaises(ValueError):
            irr([100.0, 120.0])

    def test_npv_rejects_invalid_rate(self) -> None:
        with self.assertRaises(ValueError):
            npv(-1.0, [-100.0, 120.0])


if __name__ == "__main__":
    unittest.main()

