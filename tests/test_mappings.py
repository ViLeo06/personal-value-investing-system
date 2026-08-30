from datetime import date
from decimal import Decimal

import pytest

from value_investing.mappings import (
    MappingRule,
    build_registry,
    normalize_source_label,
)


def rule(label, metric, *, priority=100, valid_from=None, valid_to=None):
    return MappingRule(
        source_code="SSE",
        source_label=label,
        canonical_metric_code=metric,
        statement_type="income_statement",
        statement_scope="consolidated",
        valid_from=valid_from,
        valid_to=valid_to,
        output_unit="currency",
        output_currency="CNY",
        priority=priority,
    )


def test_label_normalization_and_exact_resolution():
    assert normalize_source_label("  营业  收入　") == "营业 收入"
    registry = build_registry(
        "SSE",
        "v1",
        (rule("营业收入", "revenue"),),
        frozen=True,
    )
    resolved = registry.resolve(
        "营业收入",
        statement_type="income_statement",
        statement_scope="consolidated",
        period_end=date(2021, 6, 30),
    )
    assert resolved.canonical_metric_code == "revenue"
    assert len(registry.content_hash()) == 64


def test_date_bounded_mapping_selects_correct_accounting_label_version():
    registry = build_registry(
        "SSE",
        "v1",
        (
            rule(
                "营业总收入",
                "revenue_legacy",
                valid_to=date(2017, 12, 31),
            ),
            rule(
                "营业总收入",
                "revenue",
                valid_from=date(2018, 1, 1),
            ),
        ),
    )
    assert registry.resolve(
        "营业总收入",
        statement_type="income_statement",
        statement_scope="consolidated",
        period_end=date(2017, 12, 31),
    ).canonical_metric_code == "revenue_legacy"
    assert registry.resolve(
        "营业总收入",
        statement_type="income_statement",
        statement_scope="consolidated",
        period_end=date(2018, 12, 31),
    ).canonical_metric_code == "revenue"


def test_priority_resolves_alias_but_equal_priority_ambiguity_fails():
    prioritized = build_registry(
        "SSE",
        "v1",
        (
            rule("收入", "revenue", priority=10),
            rule("收入", "other_revenue", priority=20),
        ),
    )
    assert prioritized.resolve(
        "收入",
        statement_type="income_statement",
        statement_scope="consolidated",
        period_end=date(2021, 1, 1),
    ).canonical_metric_code == "revenue"

    ambiguous = build_registry(
        "SSE",
        "v2",
        (
            rule("收入", "revenue", priority=10),
            MappingRule(
                **{
                    **rule("收入", "other_revenue", priority=10).__dict__,
                    "valid_from": date(2020, 1, 1),
                }
            ),
        ),
    )
    with pytest.raises(ValueError):
        ambiguous.resolve(
            "收入",
            statement_type="income_statement",
            statement_scope="consolidated",
            period_end=date(2021, 1, 1),
        )


def test_numeric_conversion_makes_scale_and_sign_explicit():
    mapping = MappingRule(
        source_code="HKEXNEWS",
        source_label="Capital expenditure",
        canonical_metric_code="capital_expenditure",
        statement_type="cash_flow",
        scale_multiplier=Decimal("1000"),
        sign_multiplier=Decimal("-1"),
    )
    assert mapping.convert_numeric(
        Decimal("25"),
        source_scale=Decimal("1000000"),
    ) == Decimal("-25000000000")


def test_unknown_mapping_and_invalid_rule_fail_loudly():
    registry = build_registry("SSE", "v1", (rule("营业收入", "revenue"),))
    with pytest.raises(KeyError):
        registry.resolve(
            "模糊标签",
            statement_type="income_statement",
            statement_scope="consolidated",
            period_end=date(2021, 1, 1),
        )
    with pytest.raises(ValueError):
        MappingRule(
            source_code="SSE",
            source_label="x",
            canonical_metric_code="x",
            statement_type="income_statement",
            sign_multiplier=Decimal("0"),
        ).validate()
