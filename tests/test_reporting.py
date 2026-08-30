from datetime import date, datetime, timedelta, timezone

from value_investing.contracts import ContractCheck, Readiness
from value_investing.data_quality import RunQualityContext, evaluate_run_quality
from value_investing.reporting import (
    DecisionSummary,
    EvidenceReference,
    OutcomeSummary,
    ResearchReport,
    ReverseExpectation,
    ScenarioValuation,
    render_markdown,
)


UTC = timezone.utc
NOW = datetime(2026, 8, 30, 10, 0, tzinfo=UTC)
HASH_A = "a" * 64
HASH_B = "b" * 64
HASH_C = "c" * 64


def quality():
    contract = ContractCheck(
        model_family="owner_earnings_dcf",
        readiness=Readiness.VALIDATED,
        missing_metrics=(),
        future_metrics=(),
        unit_errors=(),
        unhashed_metrics=(),
        provisional_metrics=(),
    )
    return evaluate_run_quality(
        RunQualityContext(
            cutoff=NOW,
            contract_check=contract,
            all_required_evidence_hashed=True,
            evidence_durable=True,
            input_hash_present=True,
            output_hash_present=True,
            parameter_set_frozen=True,
            calendar_version_frozen=True,
            market_price_authoritative=True,
            corporate_actions_complete=True,
            exact_daily_total_return=True,
            phase_a_frozen_at=NOW,
            phase_b_revealed_at=NOW + timedelta(days=1),
            release_manifest_complete=True,
        )
    )


def report():
    return ResearchReport(
        run_id="run-1",
        issuer_code="KWEICHOW_MOUTAI",
        security_code="600519.SH",
        as_of_at=NOW,
        model_family="owner_earnings_dcf",
        model_version="1.0.0",
        snapshot_hash=HASH_A,
        parameter_set_hash=HASH_B,
        quality_rule_set_hash=HASH_C,
        quality=quality(),
        assumptions={
            "base": {"growth": 0.10, "discount_rate": 0.09},
            "pessimistic": {"growth": 0.05, "discount_rate": 0.11},
        },
        scenarios=(
            ScenarioValuation("base", 1000, 1500, 746, 0.12, 0.65),
            ScenarioValuation("pessimistic", 800, 1000, 497, 0.05, 0.55),
        ),
        reverse_expectation=ReverseExpectation(
            "growth",
            0.18,
            -0.30,
            0.60,
            0.000001,
            True,
        ),
        decision=DecisionSummary(
            market_price=1586,
            signal="avoid_at_price",
            safety_margin=-0.37,
            target_return=0.15,
            falsification_conditions=("现金转化率持续恶化", "渠道库存异常"),
        ),
        evidence=(
            EvidenceReference(
                title="2021 Interim Report",
                source_code="SSE",
                source_url="https://static.sse.com.cn/example.pdf",
                content_sha256=HASH_A,
                published_at=NOW - timedelta(days=1),
                available_at=NOW - timedelta(hours=23),
                storage_uri="supabase://research-evidence/sha256/aa/" + HASH_A,
            ),
        ),
        outcome=OutcomeSummary(
            start_date=date(2021, 8, 31),
            end_date=date(2026, 8, 31),
            matured=True,
            total_return=0.20,
            benchmark_return=0.30,
            excess_return=-0.10,
            outcome_method="exact_daily_total_return",
        ),
        attribution={"operating_growth": 0.5, "multiple_change": -0.3},
    )


def test_report_hash_and_markdown_are_deterministic():
    first = report()
    second = report()
    assert first.content_hash() == second.content_hash()
    markdown = render_markdown(first)
    assert "KWEICHOW_MOUTAI / 600519.SH" in markdown
    assert first.content_hash() in markdown
    assert "avoid_at_price" in markdown
    assert "exact_daily_total_return" in markdown
    assert "报告文本不是数据库" in markdown


def test_evidence_table_escapes_markdown():
    original = report()
    reference = EvidenceReference(
        **{
            **original.evidence[0].__dict__,
            "title": "Title | with pipe",
        }
    )
    changed = ResearchReport(
        **{
            **original.__dict__,
            "evidence": (reference,),
        }
    )
    assert "Title \\| with pipe" in render_markdown(changed)


def test_unmatured_outcome_is_rendered_without_fake_return():
    original = report()
    changed = ResearchReport(
        **{
            **original.__dict__,
            "outcome": OutcomeSummary(
                start_date=date(2025, 1, 1),
                end_date=None,
                matured=False,
            ),
        }
    )
    markdown = render_markdown(changed)
    assert "尚未成熟" in markdown
    assert "总回报：—" in markdown
