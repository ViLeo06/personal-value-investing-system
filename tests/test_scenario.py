import unittest

from pvis.scenario import Scenario, analyze_scenarios


class ScenarioTests(unittest.TestCase):
    def test_three_scenarios(self) -> None:
        result = analyze_scenarios(
            entry_price=100.0,
            scenarios=[
                Scenario("悲观", 0.25, (0.0, 0.0, 0.0, 0.0, 0.0), 80.0),
                Scenario("基准", 0.50, (1.0, 1.0, 1.0, 1.0, 1.0), 160.0),
                Scenario("乐观", 0.25, (2.0, 2.0, 2.0, 2.0, 2.0), 240.0),
            ],
        )
        self.assertEqual(len(result["scenarios"]), 3)
        self.assertGreater(result["probability_weighted_target_entry_price"], 0)

    def test_probabilities_must_sum_to_one(self) -> None:
        with self.assertRaises(ValueError):
            analyze_scenarios(
                entry_price=100.0,
                scenarios=[Scenario("基准", 0.8, (0.0, 0.0), 120.0)],
            )


if __name__ == "__main__":
    unittest.main()

