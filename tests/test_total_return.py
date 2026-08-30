import pytest

from value_investing.legacy_gate0 import GATE0, decision_is_calibrated, realized_results


EXPECTED = {
    "KWEICHOW_MOUTAI": (1.1566638034040813, -0.053811085412071136, -0.01100164070499099),
    "TENCENT": (1.129532202854719, 0.10382794920452554, 0.019953276118132024),
    "BYD": (3.0988153247723593, 0.014585348735625114, 0.002900198584654401),
    "CMB": (1.2701437226284904, 0.03158215656204533, 0.0062381161097595506),
}


def test_gate0_total_return_reconstruction():
    results = realized_results()
    for issuer_code, (shares, total_return, cagr) in EXPECTED.items():
        result = results[issuer_code]
        assert result.final_shares == pytest.approx(shares, abs=1e-12)
        assert result.total_return == pytest.approx(total_return, abs=1e-12)
        assert result.annualized_return == pytest.approx(cagr, abs=1e-12)


def test_gate0_hurdle_classification_is_four_of_four():
    results = realized_results()
    assert all(
        decision_is_calibrated(GATE0[code].base_predicted_irr, result.annualized_return)
        for code, result in results.items()
    )


def test_byd_three_for_one_share_multiplier_is_applied():
    result = realized_results()["BYD"]
    split_entries = [entry for entry in result.entries if entry.event.share_multiplier != 1.0]
    assert len(split_entries) == 1
    assert split_entries[0].event.share_multiplier == 3.0
