"""Native V1.2 Tencent replay for the 2021-08-30 decision timestamp.

The model uses contemporaneous 2021H1 disclosures plus an explicit FCFF/SOTP
scenario policy. Official filing bytes and an authoritative historical market
file are not yet retained, so the run remains data-provisional and is never
tuned to reproduce the frozen legacy workbook.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, replace
from typing import Mapping

from .decision import DecisionResult, classify_five_year_opportunity
from .fcff import ValueDriverFcffAssumptions
from .hashing import sha256_hex
from .platform import (
    PlatformScenarioAssumptions,
    PlatformScenarioResult,
    value_platform_scenario,
)
from .sotp import SotPComponent
from .valuation import SolveResult, bounded_bisection
from .value_driver_holding import (
    ValueDriverHoldingResult,
    value_driver_holding_result,
)


@dataclass(frozen=True)
class TencentInterimFacts:
    half_year_revenue_rmb_bn: float
    half_year_non_ifrs_operating_profit_rmb_bn: float
    half_year_ifrs_parent_profit_rmb_bn: float
    basic_eps_rmb: float
    total_cash_rmb_bn: float
    net_debt_rmb_bn: float
    listed_investee_fair_value_rmb_bn: float
    value_added_services_q2_revenue_rmb_bn: float
    online_advertising_q2_revenue_rmb_bn: float
    fintech_business_services_q2_revenue_rmb_bn: float
    cny_to_hkd: float
    current_price_hkd: float
    filing_publication_date: str
    earliest_usable_at: str
    disclosure_url: str
    market_price_source: str
    fx_source: str

    @property
    def inferred_weighted_average_shares_bn(self) -> float:
        return self.half_year_ifrs_parent_profit_rmb_bn / self.basic_eps_rmb

    @property
    def annualized_revenue_rmb_bn(self) -> float:
        return self.half_year_revenue_rmb_bn * 2.0

    @property
    def operating_margin_anchor(self) -> float:
        return (
            self.half_year_non_ifrs_operating_profit_rmb_bn
            / self.half_year_revenue_rmb_bn
        )


@dataclass(frozen=True)
class TencentScenarioOutput:
    assumptions: PlatformScenarioAssumptions
    result: PlatformScenarioResult
    holding: ValueDriverHoldingResult
    intrinsic_value_per_share_hkd: float
    five_year_irr: float
    target_buy_price_15pct: float


@dataclass(frozen=True)
class NativeTencentRun:
    issuer_code: str
    security_code: str
    decision_at: str
    current_price_hkd: float
    facts: TencentInterimFacts
    scenarios: Mapping[str, TencentScenarioOutput]
    reverse_growth_multiplier: SolveResult
    reverse_implied_first_year_growth: float
    decision: DecisionResult
    input_hash: str
    output_hash: str
    legacy_base_value_hkd: float
    native_minus_legacy_base_hkd: float
    realized_proxy_cagr: float
    base_forecast_error: float


def _fade_path(
    first_five: tuple[float, float, float, float, float],
    terminal: float,
    *,
    explicit_years: int = 15,
) -> tuple[float, ...]:
    if explicit_years < len(first_five):
        raise ValueError("explicit_years cannot be below the initial path length")
    remaining = explicit_years - len(first_five)
    if remaining == 0:
        return first_five
    start = first_five[-1]
    return first_five + tuple(
        start + (terminal - start) * step / remaining
        for step in range(1, remaining + 1)
    )


def default_tencent_2021_facts() -> TencentInterimFacts:
    return TencentInterimFacts(
        half_year_revenue_rmb_bn=273.562,
        half_year_non_ifrs_operating_profit_rmb_bn=85.6,
        half_year_ifrs_parent_profit_rmb_bn=90.354,
        basic_eps_rmb=9.492,
        total_cash_rmb_bn=255.2,
        net_debt_rmb_bn=21.0,
        listed_investee_fair_value_rmb_bn=1_446.0,
        value_added_services_q2_revenue_rmb_bn=72.0,
        online_advertising_q2_revenue_rmb_bn=22.8,
        fintech_business_services_q2_revenue_rmb_bn=41.9,
        cny_to_hkd=1.2042,
        current_price_hkd=465.8,
        filing_publication_date="2021-08-18",
        earliest_usable_at="2021-08-19T09:30:00+08:00",
        disclosure_url=(
            "https://www.prnewswire.com/news-releases/"
            "tencent-announces-2021-second-quarter-and-interim-results-"
            "301357768.html"
        ),
        market_price_source="legacy_workbook_frozen_close_pending_authoritative_file",
        fx_source="free_secondary_2021-08-30_close_pending_authoritative_file",
    )


def _scenario_assumptions(
    facts: TencentInterimFacts,
) -> dict[str, PlatformScenarioAssumptions]:
    common = {
        "starting_revenue": facts.annualized_revenue_rmb_bn,
        "starting_operating_margin": facts.operating_margin_anchor,
        "tax_rate": 0.20,
    }
    policies = {
        "pessimistic": {
            "growth": (0.070, 0.065, 0.060, 0.055, 0.050),
            "terminal_growth": 0.020,
            "margins": (0.290, 0.285, 0.280, 0.275, 0.270),
            "terminal_margin": 0.240,
            "ronic": (0.180, 0.180, 0.170, 0.160, 0.150),
            "terminal_ronic": 0.090,
            "wacc": 0.110,
            "investment_holding_discount": 0.55,
        },
        "base": {
            "growth": (0.130, 0.120, 0.110, 0.100, 0.090),
            "terminal_growth": 0.030,
            "margins": (0.310, 0.307, 0.304, 0.300, 0.296),
            "terminal_margin": 0.260,
            "ronic": (0.270, 0.260, 0.250, 0.230, 0.210),
            "terminal_ronic": 0.105,
            "wacc": 0.100,
            "investment_holding_discount": 0.35,
        },
        "optimistic": {
            "growth": (0.170, 0.160, 0.145, 0.130, 0.115),
            "terminal_growth": 0.035,
            "margins": (0.325, 0.323, 0.320, 0.316, 0.312),
            "terminal_margin": 0.285,
            "ronic": (0.320, 0.310, 0.300, 0.280, 0.260),
            "terminal_ronic": 0.120,
            "wacc": 0.090,
            "investment_holding_discount": 0.25,
        },
    }
    result: dict[str, PlatformScenarioAssumptions] = {}
    for name, policy in policies.items():
        operating = ValueDriverFcffAssumptions(
            starting_revenue=common["starting_revenue"],
            starting_operating_margin=common["starting_operating_margin"],
            tax_rate=common["tax_rate"],
            revenue_growth=_fade_path(
                policy["growth"], policy["terminal_growth"]
            ),
            operating_margins=_fade_path(
                policy["margins"], policy["terminal_margin"]
            ),
            ronic=_fade_path(policy["ronic"], policy["terminal_ronic"]),
            wacc=policy["wacc"],
            terminal_growth=policy["terminal_growth"],
            terminal_ronic=policy["terminal_ronic"],
        )
        result[name] = PlatformScenarioAssumptions(
            operating=operating,
            investment_components=(
                SotPComponent(
                    name="listed_investments",
                    gross_value=facts.listed_investee_fair_value_rmb_bn,
                    holding_discount=policy["investment_holding_discount"],
                ),
            ),
            non_operating_assets=0.0,
            debt=facts.net_debt_rmb_bn,
            minority_interest=0.0,
            other_claims=0.0,
            shares_outstanding=facts.inferred_weighted_average_shares_bn,
        )
    return result


def _equity_bridge(assumptions: PlatformScenarioAssumptions) -> float:
    investment_value = sum(
        component.attributable_value
        for component in assumptions.investment_components
    )
    return (
        investment_value
        + assumptions.non_operating_assets
        - assumptions.debt
        - assumptions.minority_interest
        - assumptions.other_claims
    )


def build_native_tencent_2021_run() -> NativeTencentRun:
    facts = default_tencent_2021_facts()
    assumptions_by_scenario = _scenario_assumptions(facts)
    scenario_outputs: dict[str, TencentScenarioOutput] = {}
    for name, assumptions in assumptions_by_scenario.items():
        result = value_platform_scenario(assumptions)
        holding = value_driver_holding_result(
            result.operating_result,
            discount_rate=assumptions.operating.wacc,
            equity_bridge_value=_equity_bridge(assumptions),
            shares_outstanding=assumptions.shares_outstanding,
            current_price=facts.current_price_hkd,
            reporting_to_quote_fx=facts.cny_to_hkd,
            target_return=0.15,
        )
        scenario_outputs[name] = TencentScenarioOutput(
            assumptions=assumptions,
            result=result,
            holding=holding,
            intrinsic_value_per_share_hkd=(
                result.intrinsic_value_per_share * facts.cny_to_hkd
            ),
            five_year_irr=holding.annualized_return,
            target_buy_price_15pct=holding.target_buy_price,
        )

    base = assumptions_by_scenario["base"]

    def reverse_objective(multiplier: float) -> float:
        candidate_operating = replace(
            base.operating,
            revenue_growth=tuple(
                growth * multiplier for growth in base.operating.revenue_growth
            ),
        )
        candidate = replace(base, operating=candidate_operating)
        return (
            value_platform_scenario(candidate).intrinsic_value_per_share
            * facts.cny_to_hkd
            - facts.current_price_hkd
        )

    reverse = bounded_bisection(
        reverse_objective,
        0.0,
        5.0,
        tolerance=1e-9,
    )
    if not reverse.converged or reverse.value is None:
        raise RuntimeError("Tencent Reverse DCF did not converge")
    reverse_first_year_growth = (
        base.operating.revenue_growth[0] * reverse.value
    )
    decision = classify_five_year_opportunity(
        {
            name: output.five_year_irr
            for name, output in scenario_outputs.items()
        },
        hurdle=0.15,
        data_quality="provisional",
    )
    input_manifest = {
        "issuer_code": "TENCENT",
        "security_code": "0700.HK",
        "decision_at": "2021-08-30T16:00:00+08:00",
        "facts": asdict(facts),
        "scenario_assumptions": {
            name: asdict(output.assumptions)
            for name, output in scenario_outputs.items()
        },
        "policy_version": "platform_fcff_sotp_policy_v1",
    }
    output_manifest = {
        "scenarios": {
            name: {
                "intrinsic_value_per_share_hkd": (
                    output.intrinsic_value_per_share_hkd
                ),
                "five_year_irr": output.five_year_irr,
                "target_buy_price_15pct": output.target_buy_price_15pct,
                "year_five_value_per_share_hkd": (
                    output.holding.value_per_share_at_horizon
                ),
                "terminal_value_share": (
                    output.result.operating_result.terminal_value_share
                ),
            }
            for name, output in scenario_outputs.items()
        },
        "reverse_growth_multiplier": reverse.value,
        "reverse_implied_first_year_growth": reverse_first_year_growth,
        "decision": asdict(decision),
    }
    legacy_base_value = 588.31
    realized_proxy_cagr = 0.019953276118132024
    base_irr = scenario_outputs["base"].five_year_irr
    return NativeTencentRun(
        issuer_code="TENCENT",
        security_code="0700.HK",
        decision_at="2021-08-30T16:00:00+08:00",
        current_price_hkd=facts.current_price_hkd,
        facts=facts,
        scenarios=scenario_outputs,
        reverse_growth_multiplier=reverse,
        reverse_implied_first_year_growth=reverse_first_year_growth,
        decision=decision,
        input_hash=sha256_hex(input_manifest),
        output_hash=sha256_hex(output_manifest),
        legacy_base_value_hkd=legacy_base_value,
        native_minus_legacy_base_hkd=(
            scenario_outputs["base"].intrinsic_value_per_share_hkd
            - legacy_base_value
        ),
        realized_proxy_cagr=realized_proxy_cagr,
        base_forecast_error=realized_proxy_cagr - base_irr,
    )
