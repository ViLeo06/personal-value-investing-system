from datetime import date

from value_investing.cohorts import (
    CohortObservation,
    intervals_overlap,
    select_non_overlapping,
    summarize_cohorts,
)


def _obs(security, decision, maturity):
    return CohortObservation(
        issuer_code=security,
        security_code=security,
        decision_date=decision,
        maturity_date=maturity,
        model_family="test",
    )


def test_overlap_uses_half_open_intervals():
    left = _obs("A", date(2015, 1, 1), date(2020, 1, 1))
    touching = _obs("A", date(2020, 1, 1), date(2025, 1, 1))
    overlapping = _obs("A", date(2019, 12, 31), date(2024, 12, 31))
    assert not intervals_overlap(left, touching)
    assert intervals_overlap(left, overlapping)


def test_non_overlapping_selection_is_per_security():
    observations = [
        _obs("A", date(2015, 1, 1), date(2020, 1, 1)),
        _obs("A", date(2016, 1, 1), date(2021, 1, 1)),
        _obs("A", date(2020, 1, 1), date(2025, 1, 1)),
        _obs("B", date(2016, 1, 1), date(2021, 1, 1)),
    ]
    selected = select_non_overlapping(observations)
    assert [(row.security_code, row.decision_date) for row in selected] == [
        ("A", date(2015, 1, 1)),
        ("B", date(2016, 1, 1)),
        ("A", date(2020, 1, 1)),
    ]


def test_summary_separates_mature_and_pending():
    observations = [
        _obs("A", date(2015, 1, 1), date(2020, 1, 1)),
        _obs("A", date(2022, 1, 1), date(2027, 1, 1)),
        _obs("B", date(2016, 1, 1), date(2021, 1, 1)),
    ]
    summary = summarize_cohorts(observations, date(2026, 8, 30))
    assert summary.total_observations == 3
    assert summary.mature_observations == 2
    assert summary.pending_observations == 1
    assert summary.unique_issuers == 2
    assert summary.unique_decision_dates == 3
    assert len(summary.non_overlapping_observations) == 2
