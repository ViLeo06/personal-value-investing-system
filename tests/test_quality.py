from value_investing.quality import (
    AllocationEligibility,
    EvidenceQuality,
    QualityIssue,
    evaluate_quality_gate,
)


def test_official_clean_evidence_is_eligible():
    result = evaluate_quality_gate(
        [EvidenceQuality.OFFICIAL, EvidenceQuality.RECONCILED], []
    )
    assert result.eligibility == AllocationEligibility.ELIGIBLE


def test_provisional_moutai_chain_is_research_only():
    result = evaluate_quality_gate(
        [EvidenceQuality.OFFICIAL, EvidenceQuality.DERIVED_ARCHIVE, EvidenceQuality.PROXY],
        [
            QualityIssue(
                "PROVISIONAL_HISTORICAL_CLOSE",
                "warning",
                "Historical close is not yet authoritative.",
            )
        ],
    )
    assert result.eligibility == AllocationEligibility.BLOCKED
    assert "PROVISIONAL_HISTORICAL_CLOSE" in result.blocking_codes


def test_derived_but_nonblocking_data_remains_research_only():
    result = evaluate_quality_gate(
        [EvidenceQuality.DERIVED_ARCHIVE],
        [QualityIssue("NOTE", "info", "Research note", blocks_allocation=False)],
    )
    assert result.eligibility == AllocationEligibility.RESEARCH_ONLY
