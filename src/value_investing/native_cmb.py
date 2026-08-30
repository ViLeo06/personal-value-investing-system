"""Native V1.2 CMB replay for the 2021-08-30 decision timestamp.

The run uses only contemporaneous 2021H1 bank facts plus a published scenario
policy. It is intentionally separate from the frozen legacy workbook and does
not tune assumptions to reproduce the legacy valuation.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Mapping

from .bank_normalization import BankNormalization, normalize_cmb_residual_income_v1
from .decision import DecisionResult, classify_five_year_opportunity
from .hashing import sha256_hex
from .residual_income import (
    ResidualIncomeAssumptions,
    ResidualIncomeResult,
    implied_uniform_roe,
    value_residual_income,
)
from .residual_income_investment import (
    residual_income_economic_irr,
    residual_income_holding_value,
    residual_income_target_buy_price,
)


@dataclass(frozen=True)
class ScenarioOutput:
    assumptions: ResidualIncomeAssumptions
    result: ResidualIncomeResult
    year_five_value_per_share: float
    five_year_irr: float
    target_buy_price_15pct: float


@dataclass(frozen=True)
class NativeCmbRun:
    issuer_code: str
    security_code: str
    decision_at: str
    current_price: float
    normalization: BankNormalization
    scenarios: Mapping[str, ScenarioOutput]
    reverse_implied_uniform_roe: float
    decision: DecisionResult
    input_hash: str
    output_hash: str
    legacy_base_value: float
    native_minus_legacy_base: float
    realized_proxy_cagr: float
    base_forecast_error: float


def build_native_cmb_2021_run() -> NativeCmbRun:
    normalization = normalize_cmb_residual_income_v1(
        book_value_per_share=26.60,
        annualized_roe=0.1806,
        half_year_eps=2.35,
        net_interest_margin=0.0249,
        credit_cost=0.0056,
        cost_income_ratio=0.2795,
        non_performing_loan_ratio=0.0101,
        common_equity_tier1_ratio=0.1189,
    )
    policy = {
        "pessimistic": {
            "roe_path": (
                0.145,
                0.135,
                0.125,
                0.115,
                0.105,
                0.100,
                0.095,
                0.090,
                0.085,
                0.080,
            ),
            "payout": 0.40,
            "cost_of_equity": 0.120,
            "terminal_roe": 0.095,
            "terminal_growth": 0.020,
        },
        "base": {
            "roe_path": (
                0.170,
                0.160,
                0.150,
                0.140,
                0.130,
                0.125,
                0.120,
                0.115,
                0.110,
                0.105,
            ),
            "payout": 0.35,
            "cost_of_equity": 0.105,
            "terminal_roe": 0.115,
            "terminal_growth": 0.030,
        },
        "optimistic": {
            "roe_path": (
                0.180,
                0.175,
                0.170,
                0.165,
                0.160,
                0.155,
                0.150,
                0.145,
                0.140,
                0.135,
            ),
            "payout": 0.32,
            "cost_of_equity": 0.095,
            "terminal_roe": 0.125,
            "terminal_growth": 0.035,
        },
    }

    scenario_outputs: dict[str, ScenarioOutput] = {}
    for scenario, parameters in policy.items():
        assumptions = ResidualIncomeAssumptions(
            opening_book_value_per_share=normalization.opening_book_value_per_share,
            roe_path=parameters["roe_path"],
            payout_ratio_path=[parameters["payout"]] * 10,
            cost_of_equity=parameters["cost_of_equity"],
            terminal_roe=parameters["terminal_roe"],
            terminal_growth=parameters["terminal_growth"],
        )
        result = value_residual_income(assumptions)
        irr = residual_income_economic_irr(48.45, result, assumptions)
        if not irr.converged or irr.value is None:
            raise RuntimeError(f"IRR did not converge for {scenario}")
        scenario_outputs[scenario] = ScenarioOutput(
            assumptions=assumptions,
            result=result,
            year_five_value_per_share=residual_income_holding_value(
                result, assumptions
            ),
            five_year_irr=irr.value,
            target_buy_price_15pct=residual_income_target_buy_price(
                result, assumptions, 0.15
            ),
        )

    reverse = implied_uniform_roe(
        48.45,
        scenario_outputs["base"].assumptions,
    )
    if not reverse.converged or reverse.value is None:
        raise RuntimeError("Reverse residual-income solve did not converge")

    decision = classify_five_year_opportunity(
        {
            name: output.five_year_irr
            for name, output in scenario_outputs.items()
        },
        hurdle=0.15,
        data_quality="provisional",
    )
    input_manifest = {
        "issuer_code": "CMB",
        "security_code": "600036.SH",
        "decision_at": "2021-08-30T15:00:00+08:00",
        "current_price": 48.45,
        "normalization": asdict(normalization),
        "scenario_assumptions": {
            name: asdict(output.assumptions)
            for name, output in scenario_outputs.items()
        },
        "policy_version": "bank_scenario_policy_v1",
    }
    output_manifest = {
        "scenarios": {
            name: {
                "intrinsic_value_per_share": output.result.intrinsic_value_per_share,
                "five_year_irr": output.five_year_irr,
                "target_buy_price_15pct": output.target_buy_price_15pct,
                "year_five_value_per_share": output.year_five_value_per_share,
                "terminal_value_share": output.result.terminal_value_share,
            }
            for name, output in scenario_outputs.items()
        },
        "reverse_implied_uniform_roe": reverse.value,
        "decision": asdict(decision),
    }
    realized_proxy_cagr = 0.0062381161097595506
    legacy_base_value = 40.30
    base_irr = scenario_outputs["base"].five_year_irr
    return NativeCmbRun(
        issuer_code="CMB",
        security_code="600036.SH",
        decision_at="2021-08-30T15:00:00+08:00",
        current_price=48.45,
        normalization=normalization,
        scenarios=scenario_outputs,
        reverse_implied_uniform_roe=reverse.value,
        decision=decision,
        input_hash=sha256_hex(input_manifest),
        output_hash=sha256_hex(output_manifest),
        legacy_base_value=legacy_base_value,
        native_minus_legacy_base=(
            scenario_outputs["base"].result.intrinsic_value_per_share
            - legacy_base_value
        ),
        realized_proxy_cagr=realized_proxy_cagr,
        base_forecast_error=realized_proxy_cagr - base_irr,
    )
