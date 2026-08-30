from datetime import date

import pytest

from value_investing.model_router import ModelAssignment, ModelFamily, route_model


def test_effective_dated_model_route():
    assignments = [
        ModelAssignment(
            "COMPANY",
            ModelFamily.VALUE_DRIVER_FCFF,
            date(2010, 1, 1),
            date(2020, 12, 31),
        ),
        ModelAssignment(
            "COMPANY",
            ModelFamily.HOLDING_COMPANY_SOTP,
            date(2021, 1, 1),
        ),
    ]
    assert route_model(assignments, "COMPANY", date(2020, 6, 30)).model_family == ModelFamily.VALUE_DRIVER_FCFF
    assert route_model(assignments, "COMPANY", date(2021, 6, 30)).model_family == ModelFamily.HOLDING_COMPANY_SOTP


def test_overlapping_routes_fail_closed():
    assignments = [
        ModelAssignment("COMPANY", ModelFamily.VALUE_DRIVER_FCFF, date(2020, 1, 1)),
        ModelAssignment("COMPANY", ModelFamily.FCFF_SOTP, date(2020, 1, 1)),
    ]
    with pytest.raises(ValueError, match="overlapping"):
        route_model(assignments, "COMPANY", date(2021, 1, 1))
