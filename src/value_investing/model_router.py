"""Versioned issuer-to-model-family routing."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from enum import StrEnum
from typing import Iterable


class ModelFamily(StrEnum):
    OWNER_EARNINGS_DCF = "owner_earnings_dcf"
    FCFF_SOTP = "fcff_sotp"
    VALUE_DRIVER_FCFF = "value_driver_fcff"
    RESIDUAL_INCOME = "residual_income"
    INSURANCE = "insurance"
    NAV = "nav"
    RESOURCE_MID_CYCLE = "resource_mid_cycle"
    HOLDING_COMPANY_SOTP = "holding_company_sotp"


@dataclass(frozen=True)
class ModelAssignment:
    issuer_code: str
    model_family: ModelFamily
    valid_from: date
    valid_to: date | None = None
    rationale: str = ""

    def applies(self, as_of: date) -> bool:
        return self.valid_from <= as_of and (
            self.valid_to is None or as_of <= self.valid_to
        )


def route_model(
    assignments: Iterable[ModelAssignment], issuer_code: str, as_of: date
) -> ModelAssignment:
    matches = [
        assignment
        for assignment in assignments
        if assignment.issuer_code == issuer_code and assignment.applies(as_of)
    ]
    if not matches:
        raise LookupError(f"no model assignment for {issuer_code} at {as_of}")
    if len(matches) > 1:
        raise ValueError(
            f"overlapping model assignments for {issuer_code} at {as_of}: {len(matches)}"
        )
    return matches[0]
