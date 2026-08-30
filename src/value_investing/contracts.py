"""Model-family data contracts and run-readiness classification.

The valuation modules consume canonical metrics only. Provider-specific field
names must be mapped before reaching this layer.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from typing import Iterable, Mapping


class Readiness(str, Enum):
    VALIDATED = "validated"
    PROVISIONAL = "provisional"
    BLOCKED = "blocked"


class EvidenceTier(str, Enum):
    OFFICIAL_BINARY = "official_binary"
    OFFICIAL_HTML = "official_html"
    DERIVED_OFFICIAL = "derived_official"
    OPEN_SOURCE_CROSS_CHECK = "open_source_cross_check"
    AGGREGATOR = "aggregator"
    MANUAL_PROXY = "manual_proxy"


@dataclass(frozen=True)
class MetricObservation:
    metric_code: str
    value: float | str
    unit: str | None
    available_at: datetime
    evidence_tier: EvidenceTier
    record_hash: str | None = None


@dataclass(frozen=True)
class ContractCheck:
    model_family: str
    readiness: Readiness
    missing_metrics: tuple[str, ...]
    future_metrics: tuple[str, ...]
    unit_errors: tuple[str, ...]
    unhashed_metrics: tuple[str, ...]
    provisional_metrics: tuple[str, ...]

    @property
    def is_usable(self) -> bool:
        return self.readiness is not Readiness.BLOCKED


MODEL_REQUIRED_METRICS: Mapping[str, frozenset[str]] = {
    "owner_earnings_dcf": frozenset(
        {
            "revenue",
            "net_income_parent",
            "operating_cash_flow",
            "maintenance_capex",
            "shares_outstanding",
        }
    ),
    "fcff_sotp": frozenset(
        {
            "revenue",
            "ebit",
            "tax_rate_normalized",
            "sales_to_capital",
            "non_operating_assets",
            "net_debt",
            "shares_outstanding",
        }
    ),
    "value_driver_fcff": frozenset(
        {
            "nopat",
            "ronic",
            "net_debt",
            "shares_outstanding",
        }
    ),
    "residual_income": frozenset(
        {
            "book_value_per_share",
            "roe",
            "payout_ratio",
            "cost_of_equity",
        }
    ),
}


EXPECTED_UNITS: Mapping[str, frozenset[str]] = {
    "revenue": frozenset({"CNY", "HKD", "USD", "currency"}),
    "net_income_parent": frozenset({"CNY", "HKD", "USD", "currency"}),
    "operating_cash_flow": frozenset({"CNY", "HKD", "USD", "currency"}),
    "maintenance_capex": frozenset({"CNY", "HKD", "USD", "currency"}),
    "ebit": frozenset({"CNY", "HKD", "USD", "currency"}),
    "nopat": frozenset({"CNY", "HKD", "USD", "currency"}),
    "non_operating_assets": frozenset({"CNY", "HKD", "USD", "currency"}),
    "net_debt": frozenset({"CNY", "HKD", "USD", "currency"}),
    "shares_outstanding": frozenset({"shares"}),
    "book_value_per_share": frozenset(
        {"CNY/share", "HKD/share", "USD/share", "currency/share"}
    ),
    "tax_rate_normalized": frozenset({"ratio"}),
    "sales_to_capital": frozenset({"ratio"}),
    "ronic": frozenset({"ratio"}),
    "roe": frozenset({"ratio"}),
    "payout_ratio": frozenset({"ratio"}),
    "cost_of_equity": frozenset({"ratio"}),
}


_PROVISIONAL_TIERS = {
    EvidenceTier.AGGREGATOR,
    EvidenceTier.MANUAL_PROXY,
    EvidenceTier.OPEN_SOURCE_CROSS_CHECK,
}


def validate_model_inputs(
    model_family: str,
    observations: Iterable[MetricObservation],
    *,
    cutoff: datetime,
) -> ContractCheck:
    """Validate canonical metrics against a model-family PIT contract.

    Multiple observations for one metric are allowed. The latest observation
    available by ``cutoff`` is selected deterministically by ``available_at``.
    """
    if cutoff.tzinfo is None:
        raise ValueError("cutoff must be timezone-aware")
    try:
        required = MODEL_REQUIRED_METRICS[model_family]
    except KeyError as exc:
        raise ValueError(f"unknown model family: {model_family}") from exc

    grouped: dict[str, list[MetricObservation]] = {}
    future: set[str] = set()
    for observation in observations:
        if observation.available_at.tzinfo is None:
            raise ValueError(
                f"available_at must be timezone-aware for {observation.metric_code}"
            )
        grouped.setdefault(observation.metric_code, []).append(observation)
        if observation.available_at > cutoff:
            future.add(observation.metric_code)

    selected: dict[str, MetricObservation] = {}
    for metric_code, candidates in grouped.items():
        eligible = [item for item in candidates if item.available_at <= cutoff]
        if eligible:
            selected[metric_code] = max(eligible, key=lambda item: item.available_at)

    missing = sorted(required - selected.keys())
    unit_errors: list[str] = []
    unhashed: list[str] = []
    provisional: list[str] = []
    for metric_code in sorted(required & selected.keys()):
        observation = selected[metric_code]
        expected = EXPECTED_UNITS.get(metric_code)
        if expected and observation.unit not in expected:
            unit_errors.append(metric_code)
        if not observation.record_hash:
            unhashed.append(metric_code)
        if observation.evidence_tier in _PROVISIONAL_TIERS:
            provisional.append(metric_code)

    if missing or unit_errors:
        readiness = Readiness.BLOCKED
    elif unhashed or provisional:
        readiness = Readiness.PROVISIONAL
    else:
        readiness = Readiness.VALIDATED

    return ContractCheck(
        model_family=model_family,
        readiness=readiness,
        missing_metrics=tuple(missing),
        future_metrics=tuple(sorted(future)),
        unit_errors=tuple(unit_errors),
        unhashed_metrics=tuple(unhashed),
        provisional_metrics=tuple(provisional),
    )
