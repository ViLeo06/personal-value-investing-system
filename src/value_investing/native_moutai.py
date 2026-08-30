"""Native V1.2 Moutai replay for the 2021-08-30 decision timestamp.

This run is intentionally distinct from the frozen legacy workbook. It uses a
published, deterministic normalization and scenario policy, then records the
reconciliation gap instead of tuning assumptions to match the old answer.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Mapping

from .decision import DecisionResult, classify_five_year_opportunity
from .hashing import sha256_hex
from .normalization import OwnerEarningsNormalization, normalize_moutai_owner_earnings_v1
from .owner_earnings import (
    OwnerEarningsAssumptions,
    OwnerEarningsResult,
    economic_irr,
    implied_first_five_year_growth,
    target_buy_price,
    value_owner_earnings,
)


@dataclass(frozen=True)
class ScenarioOutput:
    assumptions: OwnerEarningsAssumptions
    result: OwnerEarningsResult
    five_year_irr: float
    target_buy_price_15pct: float


@dataclass(frozen=True)
class NativeMoutaiRun:
    issuer_code: str
    security_code: str
    decision_at: str
    current_price: float
    normalization: OwnerEarningsNormalization
    scenarios: Mapping[str, ScenarioOutput]
    reverse_implied_growth: float
    decision: DecisionResult
    input_hash: str
    output_hash: str
    legacy_base_value: float
    native_minus_legacy_base: float


def build_native_moutai_2021_run() -> NativeMoutaiRun:
    normalization = normalize_moutai_owner_earnings_v1(
        net_income_2020=46_697_285_429.81,
        basic_eps_2020=37.17,
        operating_cash_flow_2020=51_669_068_693.03,
        net_income_h1_2021=24_653_985_551.58,
        operating_cash_flow_h1_2021=21_719_470_732.97,
        revenue_growth_h1_2021=0.1168,
        net_income_growth_h1_2021=0.0908,
        maintenance_reserve_factor=0.95,
    )
    base_growth = normalization.growth_anchor
    policy = {
        "pessimistic": (max(0.0, base_growth - 0.04), 0.105, 0.020),
        "base": (base_growth, 0.095, 0.025),
        "optimistic": (min(0.15, base_growth + 0.03), 0.085, 0.030),
    }
    scenario_outputs: dict[str, ScenarioOutput] = {}
    for scenario, (growth, discount_rate, perpetual_growth) in policy.items():
        assumptions = OwnerEarningsAssumptions(
            starting_owner_earnings_per_share=normalization.normalized_owner_earnings_per_share,
            first_five_year_growth=growth,
            discount_rate=discount_rate,
            perpetual_growth=perpetual_growth,
            explicit_years=15,
            fade_start_year=4,
        )
        result = value_owner_earnings(assumptions)
        irr = economic_irr(1586.0, result)
        if not irr.converged or irr.value is None:
            raise RuntimeError(f"IRR did not converge for {scenario}")
        scenario_outputs[scenario] = ScenarioOutput(
            assumptions=assumptions,
            result=result,
            five_year_irr=irr.value,
            target_buy_price_15pct=target_buy_price(result, 0.15),
        )

    base_template = scenario_outputs["base"].assumptions
    reverse = implied_first_five_year_growth(1586.0, base_template)
    if not reverse.converged or reverse.value is None:
        raise RuntimeError("Reverse DCF did not converge")
    decision = classify_five_year_opportunity(
        {name: output.five_year_irr for name, output in scenario_outputs.items()},
        hurdle=0.15,
        data_quality="provisional",
    )
    input_manifest = {
        "issuer_code": "KWEICHOW_MOUTAI",
        "security_code": "600519.SH",
        "decision_at": "2021-08-30T15:00:00+08:00",
        "current_price": 1586.0,
        "normalization": asdict(normalization),
        "scenario_assumptions": {
            name: asdict(output.assumptions) for name, output in scenario_outputs.items()
        },
        "policy_version": "consumer_scenario_policy_v1",
    }
    output_manifest = {
        "scenarios": {
            name: {
                "intrinsic_value_per_share": output.result.intrinsic_value_per_share,
                "five_year_irr": output.five_year_irr,
                "target_buy_price_15pct": output.target_buy_price_15pct,
                "terminal_value_share": output.result.terminal_value_share,
            }
            for name, output in scenario_outputs.items()
        },
        "reverse_implied_growth": reverse.value,
        "decision": asdict(decision),
    }
    legacy_base = 1433.46
    return NativeMoutaiRun(
        issuer_code="KWEICHOW_MOUTAI",
        security_code="600519.SH",
        decision_at="2021-08-30T15:00:00+08:00",
        current_price=1586.0,
        normalization=normalization,
        scenarios=scenario_outputs,
        reverse_implied_growth=reverse.value,
        decision=decision,
        input_hash=sha256_hex(input_manifest),
        output_hash=sha256_hex(output_manifest),
        legacy_base_value=legacy_base,
        native_minus_legacy_base=scenario_outputs["base"].result.intrinsic_value_per_share - legacy_base,
    )
