"""Deterministic Markdown research reports from frozen run outputs."""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import date, datetime
from typing import Mapping, Sequence

from .data_quality import RunQualityAssessment


@dataclass(frozen=True)
class EvidenceReference:
    title: str
    source_code: str
    source_url: str
    content_sha256: str
    published_at: datetime | None
    available_at: datetime
    storage_uri: str | None = None

    def validate(self) -> None:
        if not self.title or not self.source_code or not self.source_url:
            raise ValueError("evidence title, source code and URL are required")
        if len(self.content_sha256) != 64:
            raise ValueError("evidence content hash must be SHA-256")
        if self.available_at.tzinfo is None:
            raise ValueError("evidence available_at must be timezone-aware")
        if self.published_at is not None:
            if self.published_at.tzinfo is None:
                raise ValueError("published_at must be timezone-aware")
            if self.available_at < self.published_at:
                raise ValueError("available_at cannot precede published_at")


@dataclass(frozen=True)
class ScenarioValuation:
    scenario: str
    intrinsic_value_per_share: float
    year_five_value_per_share: float
    target_buy_price: float
    expected_irr: float
    terminal_value_share: float


@dataclass(frozen=True)
class ReverseExpectation:
    solved_variable: str
    solution_value: float | None
    lower_bound: float | None
    upper_bound: float | None
    residual: float | None
    converged: bool


@dataclass(frozen=True)
class DecisionSummary:
    market_price: float
    signal: str
    safety_margin: float
    target_return: float
    falsification_conditions: tuple[str, ...]


@dataclass(frozen=True)
class OutcomeSummary:
    start_date: date
    end_date: date | None
    matured: bool
    total_return: float | None = None
    benchmark_return: float | None = None
    excess_return: float | None = None
    outcome_method: str | None = None


@dataclass(frozen=True)
class ResearchReport:
    run_id: str
    issuer_code: str
    security_code: str
    as_of_at: datetime
    model_family: str
    model_version: str
    snapshot_hash: str
    parameter_set_hash: str
    quality_rule_set_hash: str
    quality: RunQualityAssessment
    assumptions: Mapping[str, Mapping[str, object]]
    scenarios: tuple[ScenarioValuation, ...]
    reverse_expectation: ReverseExpectation | None
    decision: DecisionSummary
    evidence: tuple[EvidenceReference, ...]
    outcome: OutcomeSummary | None = None
    attribution: Mapping[str, object] | None = None

    def validate(self) -> None:
        if self.as_of_at.tzinfo is None:
            raise ValueError("as_of_at must be timezone-aware")
        for digest in (
            self.snapshot_hash,
            self.parameter_set_hash,
            self.quality_rule_set_hash,
        ):
            if len(digest) != 64:
                raise ValueError("run reference hashes must be SHA-256")
        if not self.scenarios:
            raise ValueError("at least one scenario is required")
        if len({item.scenario for item in self.scenarios}) != len(self.scenarios):
            raise ValueError("scenario names must be unique")
        for reference in self.evidence:
            reference.validate()
        if self.outcome is not None:
            if self.outcome.end_date is not None and self.outcome.end_date < self.outcome.start_date:
                raise ValueError("outcome end date cannot precede start date")
            if self.outcome.matured and self.outcome.end_date is None:
                raise ValueError("matured outcome requires end_date")

    def canonical_payload(self) -> dict[str, object]:
        self.validate()
        return {
            "run_id": self.run_id,
            "issuer_code": self.issuer_code,
            "security_code": self.security_code,
            "as_of_at": self.as_of_at.isoformat(),
            "model_family": self.model_family,
            "model_version": self.model_version,
            "snapshot_hash": self.snapshot_hash,
            "parameter_set_hash": self.parameter_set_hash,
            "quality_rule_set_hash": self.quality_rule_set_hash,
            "readiness": self.quality.readiness.value,
            "quality_results": [
                {
                    "rule_code": result.rule_code,
                    "severity": result.severity.value,
                    "passed": result.passed,
                    "description": result.description,
                    "details": result.details,
                }
                for result in self.quality.results
            ],
            "assumptions": {
                scenario: dict(sorted(values.items()))
                for scenario, values in sorted(self.assumptions.items())
            },
            "scenarios": [
                {
                    "scenario": item.scenario,
                    "intrinsic_value_per_share": item.intrinsic_value_per_share,
                    "year_five_value_per_share": item.year_five_value_per_share,
                    "target_buy_price": item.target_buy_price,
                    "expected_irr": item.expected_irr,
                    "terminal_value_share": item.terminal_value_share,
                }
                for item in sorted(self.scenarios, key=lambda value: value.scenario)
            ],
            "reverse_expectation": (
                self.reverse_expectation.__dict__
                if self.reverse_expectation
                else None
            ),
            "decision": {
                **self.decision.__dict__,
                "falsification_conditions": list(
                    self.decision.falsification_conditions
                ),
            },
            "evidence": [
                {
                    "title": item.title,
                    "source_code": item.source_code,
                    "source_url": item.source_url,
                    "content_sha256": item.content_sha256,
                    "published_at": (
                        item.published_at.isoformat()
                        if item.published_at
                        else None
                    ),
                    "available_at": item.available_at.isoformat(),
                    "storage_uri": item.storage_uri,
                }
                for item in sorted(
                    self.evidence,
                    key=lambda value: (
                        value.available_at,
                        value.source_code,
                        value.content_sha256,
                    ),
                )
            ],
            "outcome": self.outcome.__dict__ if self.outcome else None,
            "attribution": dict(self.attribution or {}),
        }

    def content_hash(self) -> str:
        encoded = json.dumps(
            self.canonical_payload(),
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
            default=_json_default,
        ).encode("utf-8")
        return hashlib.sha256(encoded).hexdigest()


def _json_default(value: object) -> object:
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    raise TypeError(f"unsupported JSON value: {type(value)!r}")


def _escape(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", "<br>")


def _percent(value: float | None) -> str:
    return "—" if value is None else f"{value:.2%}"


def _number(value: float | None) -> str:
    return "—" if value is None else f"{value:,.4f}"


def render_markdown(report: ResearchReport) -> str:
    report.validate()
    failed = report.quality.failed_rules
    lines = [
        f"# {report.issuer_code} / {report.security_code} 估值研究",
        "",
        "## 冻结运行",
        "",
        f"- Run ID：`{report.run_id}`",
        f"- 历史截止：`{report.as_of_at.isoformat()}`",
        f"- 模型：`{report.model_family}@{report.model_version}`",
        f"- Snapshot：`{report.snapshot_hash}`",
        f"- Parameter set：`{report.parameter_set_hash}`",
        f"- Quality rules：`{report.quality_rule_set_hash}`",
        f"- Readiness：**{report.quality.readiness.value}**",
        f"- Report hash：`{report.content_hash()}`",
        "",
        "## 估值情景",
        "",
        "| 情景 | 每股内在价值 | 五年后每股价值 | 15%目标买入价 | 预期IRR | 终值占比 |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for item in sorted(report.scenarios, key=lambda value: value.scenario):
        lines.append(
            "| "
            + " | ".join(
                (
                    _escape(item.scenario),
                    _number(item.intrinsic_value_per_share),
                    _number(item.year_five_value_per_share),
                    _number(item.target_buy_price),
                    _percent(item.expected_irr),
                    _percent(item.terminal_value_share),
                )
            )
            + " |"
        )

    lines.extend(
        [
            "",
            "## 市场隐含预期",
            "",
        ]
    )
    reverse = report.reverse_expectation
    if reverse is None:
        lines.append("未运行 Reverse DCF。")
    else:
        lines.extend(
            [
                f"- 反推变量：`{reverse.solved_variable}`",
                f"- 解：{_number(reverse.solution_value)}",
                f"- 边界：[{_number(reverse.lower_bound)}, {_number(reverse.upper_bound)}]",
                f"- 残差：{_number(reverse.residual)}",
                f"- 收敛：{reverse.converged}",
            ]
        )

    lines.extend(
        [
            "",
            "## 决策",
            "",
            f"- 历史市场价：{_number(report.decision.market_price)}",
            f"- 信号：**{report.decision.signal}**",
            f"- 安全边际：{_percent(report.decision.safety_margin)}",
            f"- 目标回报：{_percent(report.decision.target_return)}",
            "- 证伪条件：",
        ]
    )
    lines.extend(
        f"  - {_escape(condition)}"
        for condition in report.decision.falsification_conditions
    )

    lines.extend(["", "## 质量门", ""])
    if not failed:
        lines.append("全部质量规则通过。")
    else:
        lines.extend(
            [
                "| 规则 | 严重性 | 说明 |",
                "|---|---|---|",
            ]
        )
        for item in failed:
            lines.append(
                f"| `{item.rule_code}` | {item.severity.value} | "
                f"{_escape(item.description)} |"
            )

    lines.extend(
        [
            "",
            "## 证据清单",
            "",
            "| 来源 | 标题 | Published | Available | SHA-256 | Storage |",
            "|---|---|---|---|---|---|",
        ]
    )
    for item in sorted(
        report.evidence,
        key=lambda value: (
            value.available_at,
            value.source_code,
            value.content_sha256,
        ),
    ):
        lines.append(
            "| "
            + " | ".join(
                (
                    _escape(item.source_code),
                    _escape(item.title),
                    item.published_at.isoformat() if item.published_at else "—",
                    item.available_at.isoformat(),
                    f"`{item.content_sha256}`",
                    _escape(item.storage_uri or "未持久化"),
                )
            )
            + " |"
        )

    lines.extend(["", "## Phase B / 结果", ""])
    if report.outcome is None:
        lines.append("结果尚未揭晓。")
    else:
        outcome = report.outcome
        lines.extend(
            [
                f"- 区间：{outcome.start_date.isoformat()} → "
                f"{outcome.end_date.isoformat() if outcome.end_date else '尚未成熟'}",
                f"- 已成熟：{outcome.matured}",
                f"- 总回报：{_percent(outcome.total_return)}",
                f"- 基准回报：{_percent(outcome.benchmark_return)}",
                f"- 超额回报：{_percent(outcome.excess_return)}",
                f"- 口径：{_escape(outcome.outcome_method or '未注明')}",
            ]
        )

    lines.extend(
        [
            "",
            "---",
            "",
            "本报告由冻结数据生成。报告文本不是数据库，也不会反向修改模型输入。",
            "",
        ]
    )
    return "\n".join(lines)
