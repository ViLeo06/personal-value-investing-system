from datetime import date, datetime, timezone
from decimal import Decimal

import pytest

from value_investing.parsers import FactKind, ParsedFact, ParserResult


UTC = timezone.utc


def duration_fact(metric_code="revenue", value="100"):
    return ParsedFact(
        statement_type="income_statement",
        metric_code=metric_code,
        metric_label="营业收入",
        period_start=date(2021, 1, 1),
        period_end=date(2021, 6, 30),
        fiscal_year=2021,
        fiscal_period="H1",
        fact_kind=FactKind.DURATION,
        value_numeric=Decimal(value),
        unit="currency",
        currency="CNY",
        scale=Decimal("1000000"),
        source_fact_key=f"source:{metric_code}",
    )


def test_parsed_fact_hash_is_stable():
    first = duration_fact()
    second = ParsedFact(**{**first.__dict__, "metadata": {}})
    assert first.fact_hash() == second.fact_hash()


def test_parser_result_is_order_independent_and_builds_pit_rows():
    revenue = duration_fact("revenue", "100")
    profit = duration_fact("net_income_parent", "50")
    first = ParserResult(
        document_sha256="a" * 64,
        parser_name="fixture",
        parser_version="1.0.0",
        facts=(revenue, profit),
        warnings=("review label mapping",),
    )
    second = ParserResult(
        document_sha256="a" * 64,
        parser_name="fixture",
        parser_version="1.0.0",
        facts=(profit, revenue),
        warnings=("review label mapping",),
    )
    assert first.result_hash() == second.result_hash()
    rows = first.to_pit_rows(
        issuer_id="issuer",
        source_document_id="document",
        published_at=datetime(2021, 8, 18, 8, 0, tzinfo=UTC),
        available_at=datetime(2021, 8, 18, 8, 1, tzinfo=UTC),
    )
    assert len(rows) == 2
    assert rows[0]["scale"] == "1000000"
    assert len(rows[0]["record_hash"]) == 64
    assert rows[0]["metadata"]["parser_result_hash"] == first.result_hash()


def test_duration_and_instant_semantics_are_enforced():
    with pytest.raises(ValueError):
        ParsedFact(
            statement_type="income_statement",
            metric_code="revenue",
            period_end=date(2021, 6, 30),
            fact_kind=FactKind.DURATION,
            value_numeric=Decimal("1"),
        ).validate()
    with pytest.raises(ValueError):
        ParsedFact(
            statement_type="balance_sheet",
            metric_code="cash",
            period_start=date(2021, 1, 1),
            period_end=date(2021, 6, 30),
            fact_kind=FactKind.INSTANT,
            value_numeric=Decimal("1"),
        ).validate()


def test_duplicate_fact_keys_and_ambiguous_values_fail():
    duplicate = ParserResult(
        document_sha256="a" * 64,
        parser_name="fixture",
        parser_version="1",
        facts=(duration_fact(), duration_fact()),
    )
    with pytest.raises(ValueError):
        duplicate.validate()
    with pytest.raises(ValueError):
        ParsedFact(
            statement_type="notes",
            metric_code="ambiguous",
            period_end=date(2021, 6, 30),
            fact_kind=FactKind.INSTANT,
            value_numeric=Decimal("1"),
            value_text="one",
        ).validate()


def test_pit_rows_require_timezone_and_revision_integrity():
    result = ParserResult(
        document_sha256="a" * 64,
        parser_name="fixture",
        parser_version="1",
        facts=(duration_fact(),),
    )
    with pytest.raises(ValueError):
        result.to_pit_rows(
            issuer_id="issuer",
            source_document_id="document",
            published_at=None,
            available_at=datetime(2021, 8, 18),
        )
    with pytest.raises(ValueError):
        result.to_pit_rows(
            issuer_id="issuer",
            source_document_id="document",
            published_at=datetime(2021, 8, 18, tzinfo=UTC),
            available_at=datetime(2021, 8, 18, tzinfo=UTC),
            revision_no=0,
        )
