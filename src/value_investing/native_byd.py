"""Native V1.2 BYD replay for the 2021-08-30 decision timestamp.

The model uses contemporaneous 2021H1 disclosures plus an explicit
value-driver FCFF policy. The starting operating margin is a transparent
profit-before-tax proxy until archived filing bytes support a more precise EBIT
reconstruction. Market data and evidence quality therefore remain provisional.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, replace
from typing import Mapping

from .decision import DecisionResult, classify_five_year_opportunity
from .fcff import ValueDriverFcffAssumptions
from .hashing import sha256_hex
from .manufacturing import (
    ManufacturingScenarioAssumptions,
    ManufacturingScenarioResult,
    value_manufacturing_scenario,
)
from .valuation import SolveResult, bounded_bisection
from .value_driver_holding import (
    ValueDriverHoldingResult,
    value_driver_holding_result,
)


@dataclass(frozen=True)
class BydInterimFacts:
    half_year_revenue_rmb_bn: float
    half_year_parent_net_income_rmb_bn: float
    half_year_adjusted_parent_net_income_rmb_bn: float
    half_year_operating_cash_flow_rmb_bn: float
    segment_profit_before_tax_rmb_bn: float
    income_tax_expense_rmb_bn: float
    capital_expenditure_rmb_bn: float
    depreciation_amortization_rmb_bn: float
    cash_and_equivalents_rmb_bn: float
    short_term_borrowings_rmb_bn: float
    current_noncurrent_debt_rmb_bn: float
    long_term_borrowings_rmb_bn: float
    bonds_payable_rmb_bn: float
    lease_liabilities_rmb_bn: float
    minority_interest_rmb_bn: float
    parent_equity_rmb_bn: float
    shares_outstanding_bn: float
    current_price_cny: float
    filing_publication_date: str
    earliest_usable_at: str
    official_filing_url: str
    readable_mirror_url: str
    market_price_source: str

    @property
    def annualized_revenue_rmb_bn(self) -> float:
        return self.half_year_revenue_rmb_bn * 2.0

    @property
    def operating_margin_proxy(self) -> float:
        return self.segment_profit_before_tax_rmb_bn / self.half_year_revenue_rmb_bn

    @property
    def effective_tax_rate_proxy(self) -> float:
        return self.income_tax_expense_rmb_bn / self.segment_profit_before_tax_rmb_bn

    @property
    def debt_rmb_bn(self) -> float:
        return (
            self.short_term_borrowings_rmb_bn
            + self.current_noncurrent_debt_rmb_bn
            + self.long_term_borrowings_rmb_bn
            + self.bonds_payable_rmb_bn
            + self.lease_liabilities_rmb_bn
        )

    @property
    def equity_bridge_rmb_bn(self) -> float:
        return (
            self.cash_and_equivalents_rmb_bn
            - self.debt_rmb_bn
            - self.minority_interest_rmb_bn
        )


@dataclass(frozen=True)
class BydScenarioOutput:
    assumptions: ManufacturingScenarioAssumptions
    result: ManufacturingScenarioResult
    holding: ValueDriverHoldingResult
    five_year_irr: float
    target_buy_price_15pct: float


@dataclass(frozen=True)
class NativeBydRun:
    issuer_code: str
    security_code: str
    decision_at: str
    current_price_cny: float
    facts: BydInterimFacts
    scenarios: Mapping[str, BydScenarioOutput]
    reverse_growth_multiplier: SolveResult
    reverse_implied_first_year_growth: float
    decision: DecisionResult
    input_hash: str
    output_hash: str
    legacy_base_value_cny: float
    native_minus_legacy_base_cny: float
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


def default_byd_2021_facts() -> BydInterimFacts:
    return BydInterimFacts(
        half_year_revenue_rmb_bn=90.8854,
        half_year_parent_net_income_rmb_bn=1.173571,
        half_year_adjusted_parent_net_income_rmb_bn=0.368666,
        half_year_operating_cash_flow_rmb_bn=9.676845,
        segment_profit_before_tax_rmb_bn=2.204115,
        income_tax_expense_rmb_bn=0.393344,
        capital_expenditure_rmb_bn=11.132530,
        depreciation_amortization_rmb_bn=6.395985,
        cash_and_equivalents_rmb_bn=21.152299,
        short_term_borrowings_rmb_bn=11.256556,
        current_noncurrent_debt_rmb_bn=14.260446,
        long_term_borrowings_rmb_bn=10.198931,
        bonds_payable_rmb_bn=4.490423,
        lease_liabilities_rmb_bn=1.066963,
        minority_interest_rmb_bn=8.030113,
        parent_equity_rmb_bn=81.255042,
        shares_outstanding_bn=2.861143,
        current_price_cny=281.97,
        filing_publication_date="2021-08-28",
        earliest_usable_at="2021-08-30T09:30:00+08:00",
        official_filing_url=(
            "https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF"
        ),
        readable_mirror_url=(
            "https://money.finance.sina.com.cn/corp/view/"
            "vCB_AllBulletinDetail.php?id=7502467&stockid=002594"
        ),
        market_price_source="legacy_workbook_frozen_close_pending_authoritative_file",
    )


def _scenario_assumptions(
    facts: BydInterimFacts,
) -> dict[str, ManufacturingScenarioAssumptions]:
    policies = {
        "pessimistic": {
            "growth": (0.100, 0.080, 0.070, 0.060, 0.050),
            "terminal_growth": 0.020,
            "margins": (0.022, 0.023, 0.024, 0.025, 0.027),
            "terminal_margin": 0.035,
            "ronic": (0.080, 0.080, 0.080, 0.085, 0.085),
            "terminal_ronic": 0.090,
            "wacc": 0.120,
        },
        "base": {
            "growth": (0.300, 0.250, 0.200, 0.160, 0.130),
            "terminal_growth": 0.030,
            "margins": (0.030, 0.035, 0.042, 0.050, 0.057),
            "terminal_margin": 0.075,
            "ronic": (0.140, 0.140, 0.140, 0.135, 0.130),
            "terminal_ronic": 0.100,
            "wacc": 0.105,
        },
        "optimistic": {
            "growth": (0.400, 0.340, 0.280, 0.220, 0.180),
            "terminal_growth": 0.035,
            "margins": (0.032, 0.040, 0.050, 0.060, 0.070),
            "terminal_margin": 0.090,
            "ronic": (0.180, 0.180, 0.180, 0.170, 0.160),
            "terminal_ronic": 0.110,
            "wacc": 0.095,
        },
    }
    result: dict[str, ManufacturingScenarioAssumptions] = {}
    for name, policy in policies.items():
        operating = ValueDriverFcffAssumptions(
            starting_revenue=facts.annualized_revenue_rmb_bn,
            starting_operating_margin=facts.operating_margin_proxy,
            tax_rate=facts.effective_tax_rate_proxy,
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
        result[name] = ManufacturingScenarioAssumptions(
            operating=operating,
            cash_and_investments=facts.cash_and_equivalents_rmb_bn,
            debt=facts.debt_rmb_bn,
            minority_interest=facts.minority_interest_rmb_bn,
            other_non_operating_assets=0.0,
            shares_outstanding=facts.shares_outstanding_bn,
        )
    return result


def _equity_bridge(assumptions: ManufacturingScenarioAssumptions) -> float:
    return (
        assumptions.cash_and_investments
        + assumptions.other_non_operating_assets
        - assumptions.debt
        - assumptions.minority_interest
    )


def build_native_byd_2021_run() -> NativeBydRun:
    facts = default_byd_2021_facts()
    assumptions_by_scenario = _scenario_assumptions(facts)
    scenario_outputs: dict[str, BydScenarioOutput] = {}
    for name, assumptions in assumptions_by_scenario.items():
        result = value_manufacturing_scenario(assumptions)
        holding = value_driver_holding_result(
            result.operating_result,
            discount_rate=assumptions.operating.wacc,
            equity_bridge_value=_equity_bridge(assumptions),
            shares_outstanding=assumptions.shares_outstanding,
            current_price=facts.current_price_cny,
            target_return=0.15,
        )
        scenario_outputs[name] = BydScenarioOutput(
            assumptions=assumptions,
            result=result,
            holding=holding,
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
            value_manufacturing_scenario(candidate).intrinsic_value_per_share
            - facts.current_price_cny
        )

    reverse = bounded_bisection(
        reverse_objective,
        0.0,
        5.0,
        tolerance=1e-9,
    )
    if not reverse.converged or reverse.value is None:
        raise RuntimeError("BYD Reverse DCF did not converge")
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
        "issuer_code": "BYD",
        "security_code": "002594.SZ",
        "decision_at": "2021-08-30T15:00:00+08:00",
        "facts": asdict(facts),
        "scenario_assumptions": {
            name: asdict(output.assumptions)
            for name, output in scenario_outputs.items()
        },
        "policy_version": "manufacturing_value_driver_policy_v1",
    }
    output_manifest = {
        "scenarios": {
            name: {
                "intrinsic_value_per_share_cny": (
                    output.result.intrinsic_value_per_share
                ),
                "five_year_irr": output.five_year_irr,
                "target_buy_price_15pct": output.target_buy_price_15pct,
                "year_five_value_per_share_cny": (
                    output.holding.value_per_share_at_horizon
                ),
                "terminal_value_share": output.result.terminal_value_share,
                "pv_explicit_fcff": output.result.operating_result.pv_explicit_fcff,
            }
            for name, output in scenario_outputs.items()
        },
        "reverse_growth_multiplier": reverse.value,
        "reverse_implied_first_year_growth": reverse_first_year_growth,
        "decision": asdict(decision),
    }
    legacy_base_value = 22.78
    realized_proxy_cagr = 0.002900198584654401
    base_irr = scenario_outputs["base"].five_year_irr
    return NativeBydRun(
        issuer_code="BYD",
        security_code="002594.SZ",
        decision_at="2021-08-30T15:00:00+08:00",
        current_price_cny=facts.current_price_cny,
        facts=facts,
        scenarios=scenario_outputs,
        reverse_growth_multiplier=reverse,
        reverse_implied_first_year_growth=reverse_first_year_growth,
        decision=decision,
        input_hash=sha256_hex(input_manifest),
        output_hash=sha256_hex(output_manifest),
        legacy_base_value_cny=legacy_base_value,
        native_minus_legacy_base_cny=(
            scenario_outputs["base"].result.intrinsic_value_per_share
            - legacy_base_value
        ),
        realized_proxy_cagr=realized_proxy_cagr,
        base_forecast_error=realized_proxy_cagr - base_irr,
    )
