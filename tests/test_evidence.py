import unittest

from pvis.evidence import EvidenceRecord, is_point_in_time_eligible


class EvidenceTests(unittest.TestCase):
    def test_available_on_decision_date_is_eligible(self) -> None:
        self.assertTrue(is_point_in_time_eligible("2021-08-30", "2021-08-30"))

    def test_future_evidence_is_rejected(self) -> None:
        record = EvidenceRecord(
            source="官方公告",
            as_of="2021-06-30",
            available_at="2021-09-01",
            decision_at="2021-08-30",
        )
        with self.assertRaises(ValueError):
            record.validate()

    def test_as_of_cannot_follow_publication(self) -> None:
        record = EvidenceRecord(
            source="官方公告",
            as_of="2021-09-02",
            available_at="2021-09-01",
            decision_at="2021-09-01",
        )
        with self.assertRaises(ValueError):
            record.validate()


if __name__ == "__main__":
    unittest.main()

