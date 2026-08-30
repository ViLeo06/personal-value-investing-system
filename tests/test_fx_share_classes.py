import pytest

from value_investing.fx import FxBook, FxRate
from value_investing.share_classes import ShareClassClaim, allocate_issuer_equity_value


def test_direct_inverse_and_cross_fx_paths():
    book = FxBook(
        [
            FxRate("CNY", "HKD", 1.10),
            FxRate("HKD", "USD", 0.128),
        ]
    )
    assert book.convert(100.0, "CNY", "HKD").target_amount == pytest.approx(110.0)
    assert book.convert(110.0, "HKD", "CNY").target_amount == pytest.approx(100.0)
    assert book.convert(100.0, "CNY", "USD").target_amount == pytest.approx(14.08)


def test_a_and_h_equal_economic_rights_differ_only_by_fx():
    values = allocate_issuer_equity_value(
        1_000.0,
        "CNY",
        [
            ShareClassClaim("000001.SZ", "A", 60.0, 1.0, "CNY"),
            ShareClassClaim("0001.HK", "H", 40.0, 1.0, "HKD"),
        ],
        FxBook([FxRate("CNY", "HKD", 1.10)]),
    )
    by_code = {row.security_code: row for row in values}
    assert by_code["000001.SZ"].value_per_share_reporting_currency == pytest.approx(10.0)
    assert by_code["000001.SZ"].value_per_share_quote_currency == pytest.approx(10.0)
    assert by_code["0001.HK"].value_per_share_reporting_currency == pytest.approx(10.0)
    assert by_code["0001.HK"].value_per_share_quote_currency == pytest.approx(11.0)


def test_super_voting_rights_do_not_change_economic_value_unless_multiplier_changes():
    values = allocate_issuer_equity_value(
        300.0,
        "USD",
        [
            ShareClassClaim("CLASS_A", "A", 100.0, 1.0, "USD"),
            ShareClassClaim("CLASS_B", "B", 100.0, 2.0, "USD"),
        ],
        FxBook([]),
    )
    by_code = {row.security_code: row for row in values}
    assert by_code["CLASS_A"].value_per_share_quote_currency == pytest.approx(1.0)
    assert by_code["CLASS_B"].value_per_share_quote_currency == pytest.approx(2.0)
