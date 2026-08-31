from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from typing import Iterable


def add_years(value: date, years: int) -> date:
    try:
        return value.replace(year=value.year + years)
    except ValueError:
        return value.replace(month=2, day=28, year=value.year + years)


@dataclass(frozen=True, slots=True)
class Cohort:
    cohort_id: str
    decision_date: date
    horizon_years: int

    @property
    def maturity_date(self) -> date:
        return add_years(self.decision_date, self.horizon_years)

    def is_mature(self, evaluation_date: date) -> bool:
        return self.maturity_date <= evaluation_date


def mature_cohorts(cohorts: Iterable[Cohort], evaluation_date: date) -> tuple[Cohort, ...]:
    return tuple(
        sorted(
            (cohort for cohort in cohorts if cohort.is_mature(evaluation_date)),
            key=lambda cohort: cohort.decision_date,
        )
    )


def non_overlapping_cohorts(cohorts: Iterable[Cohort]) -> tuple[Cohort, ...]:
    selected: list[Cohort] = []
    for cohort in sorted(cohorts, key=lambda item: item.decision_date):
        if not selected or cohort.decision_date >= selected[-1].maturity_date:
            selected.append(cohort)
    return tuple(selected)
