import pytest

from value_investing.portfolio import (
    AllocationPolicy,
    PortfolioCandidate,
    allocate_equal_weight,
)
from value_investing.quality import AllocationEligibility


def test_only_validated_buy_candidates_receive_weight():
    result = allocate_equal_weight(
        [
            PortfolioCandidate(
                "A", "research_buy_candidate", 0.20, AllocationEligibility.ELIGIBLE
            ),
            PortfolioCandidate(
                "B", "research_buy_candidate", 0.30, AllocationEligibility.RESEARCH_ONLY
            ),
            PortfolioCandidate(
                "C", "watch_wait", 0.40, AllocationEligibility.ELIGIBLE
            ),
        ],
        AllocationPolicy(maximum_positions=5, maximum_weight=0.25, cash_buffer=0.10),
    )
    assert result.weights == (("A", 0.25),)
    assert result.cash_weight == pytest.approx(0.75)
    assert ("B", "quality_gate") in result.excluded
    assert ("C", "signal_gate") in result.excluded


def test_position_limit_uses_rank_and_leaves_cash_when_weight_capped():
    result = allocate_equal_weight(
        [
            PortfolioCandidate(
                "A", "research_buy_candidate", 0.10, AllocationEligibility.ELIGIBLE
            ),
            PortfolioCandidate(
                "B", "research_buy_candidate", 0.30, AllocationEligibility.ELIGIBLE
            ),
            PortfolioCandidate(
                "C", "research_buy_candidate", 0.20, AllocationEligibility.ELIGIBLE
            ),
        ],
        AllocationPolicy(maximum_positions=2, maximum_weight=0.30),
    )
    assert result.weights == (("B", 0.30), ("C", 0.30))
    assert result.cash_weight == pytest.approx(0.40)
    assert ("A", "position_limit") in result.excluded
