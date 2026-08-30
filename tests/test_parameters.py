from datetime import datetime, timezone

import pytest

from value_investing.parameters import (
    ParameterSet,
    ParameterSource,
    ParameterValue,
    ScenarioMonotonicRule,
    freeze_parameter_set,
)


UTC = timezone.utc
EFFECTIVE = datetime(2021, 8, 30, 7, 0, tzinfo=UTC)


def value(scenario: str, key: str, number: float) -> ParameterValue:
    return ParameterValue(
        scenario=scenario,
        key=key,
        value=number,
        unit="ratio",
        source=ParameterSource.ANALYST_JUDGMENT,
        provenance={"note": "predeclared Gate-0 scenario"},
    )


def parameter_set() -> ParameterSet:
    return ParameterSet(
        model_family="owner_earnings_dcf",
        version="moutai-2021-08-30-v1",
        effective_from=EFFECTIVE,
        issuer_code="KWEICHOW_MOUTAI",
        source_snapshot_id="00000000-0000-0000-0000-000000000001",
        values=(
            value("pessimistic", "growth", 0.05),
            value("base", "growth", 0.10),
            value("optimistic", "growth", 0.15),
            value("pessimistic", "discount_rate", 0.11),
            value("base", "discount_rate", 0.10),
            value("optimistic", "discount_rate", 0.09),
        ),
    )


def test_parameter_set_hash_is_order_independent():
    original = parameter_set()
    reordered = ParameterSet(
        model_family=original.model_family,
        version=original.version,
        effective_from=original.effective_from,
        issuer_code=original.issuer_code,
        source_snapshot_id=original.source_snapshot_id,
        values=tuple(reversed(original.values)),
    )
    assert original.content_hash() == reordered.content_hash()


def test_scenario_coherence_and_freeze():
    parameters = parameter_set()
    parameters.validate(
        required_keys={"growth", "discount_rate"},
        monotonic_rules=(
            ScenarioMonotonicRule("growth", increasing=True),
            ScenarioMonotonicRule("discount_rate", increasing=False),
        ),
    )
    frozen = freeze_parameter_set(
        parameters,
        datetime(2021, 8, 30, 8, 0, tzinfo=UTC),
    )
    assert frozen.is_frozen
    assert frozen.content_hash() != parameters.content_hash()
    with pytest.raises(ValueError):
        freeze_parameter_set(frozen, datetime(2021, 8, 30, 9, 0, tzinfo=UTC))


def test_duplicate_or_missing_parameters_fail():
    duplicate = ParameterSet(
        model_family="residual_income",
        version="v1",
        effective_from=EFFECTIVE,
        values=(value("base", "roe", 0.15), value("base", "roe", 0.14)),
    )
    with pytest.raises(ValueError):
        duplicate.validate()

    with pytest.raises(ValueError):
        parameter_set().validate(required_keys={"growth", "terminal_growth"})


def test_monotonic_rule_detects_incoherent_scenarios():
    bad = ParameterSet(
        model_family="fcff_sotp",
        version="v1",
        effective_from=EFFECTIVE,
        values=(
            value("pessimistic", "growth", 0.08),
            value("base", "growth", 0.05),
            value("optimistic", "growth", 0.12),
        ),
    )
    with pytest.raises(ValueError):
        bad.validate(
            monotonic_rules=(ScenarioMonotonicRule("growth"),)
        )
