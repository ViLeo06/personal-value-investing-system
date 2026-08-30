"""Generate a deterministic Gate-0 legacy replay report."""
from __future__ import annotations

from dataclasses import asdict
from typing import Any

from .hashing import sha256_hex
from .legacy_gate0 import GATE0, decision_is_calibrated, realized_results


def build_gate0_report() -> dict[str, Any]:
    realized = realized_results()
    rows: list[dict[str, Any]] = []
    for issuer_code in sorted(GATE0):
        frozen = GATE0[issuer_code]
        outcome = realized[issuer_code]
        rows.append(
            {
                "issuer_code": issuer_code,
                "security_code": frozen.security_code,
                "start_price": frozen.start_price,
                "end_price": frozen.end_price,
                "base_predicted_irr": frozen.base_predicted_irr,
                "realized_total_return": outcome.total_return,
                "realized_cagr": outcome.annualized_return,
                "benchmark_cagr": frozen.benchmark_cagr,
                "excess_cagr": outcome.annualized_return - frozen.benchmark_cagr,
                "decision": frozen.decision,
                "hurdle_classification_correct": decision_is_calibrated(
                    frozen.base_predicted_irr, outcome.annualized_return
                ),
                "final_shares": outcome.final_shares,
                "terminal_value": outcome.terminal_value,
            }
        )
    report = {
        "report_type": "gate0_legacy_replay",
        "source": "价值投资估值系统_历史回测_2021-2026_V1.0.xlsx",
        "source_sha256": "ec4cc507acfa6e73427172cc0e3011881c96e7b7727bfe7226e15ab6b5665e6e",
        "decision_date": "2021-08-30",
        "outcome_date": "2026-08-28",
        "holding_years": 5.0,
        "rows": rows,
    }
    report["report_hash"] = sha256_hex(report)
    return report
