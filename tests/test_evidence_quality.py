from value_investing.data.quality import (
    EvidenceAssertion,
    EvidenceGrade,
    QualityPolicy,
    evaluate_evidence,
)


def test_formal_policy_rejects_single_derived_source() -> None:
    result = evaluate_evidence(
        [
            EvidenceAssertion(
                assertion_code="reference_close_price",
                grade=EvidenceGrade.SINGLE_DERIVED,
                source_codes=("AKSHARE_EASTMONEY_DERIVED",),
                content_hashes=("a" * 64,),
            )
        ],
        QualityPolicy(required_assertions=("reference_close_price",)),
    )
    assert not result.passed
    assert result.below_grade == ("reference_close_price",)


def test_cross_validated_content_hashed_evidence_passes() -> None:
    result = evaluate_evidence(
        [
            EvidenceAssertion(
                assertion_code="reference_close_price",
                grade=EvidenceGrade.CROSS_VALIDATED,
                source_codes=("SSE", "AKSHARE_EASTMONEY_DERIVED"),
                content_hashes=("a" * 64, "b" * 64),
            )
        ],
        QualityPolicy(required_assertions=("reference_close_price",)),
    )
    assert result.passed


def test_conflict_blocks_even_official_evidence() -> None:
    result = evaluate_evidence(
        [
            EvidenceAssertion(
                assertion_code="shares_outstanding",
                grade=EvidenceGrade.OFFICIAL_PRIMARY,
                source_codes=("SSE",),
                content_hashes=("a" * 64,),
                unresolved_conflict=True,
            )
        ],
        QualityPolicy(required_assertions=("shares_outstanding",)),
    )
    assert not result.passed
    assert result.conflicts == ("shares_outstanding",)
