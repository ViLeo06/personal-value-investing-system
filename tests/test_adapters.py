from datetime import date, datetime, timezone

import pytest

from value_investing.adapters import (
    AdapterBatch,
    AdapterDocument,
    AdapterFact,
    AdapterResult,
    DataSourcePolicy,
    validate_adapter_result,
)


HASH_A = "a" * 64
HASH_B = "b" * 64
HASH_C = "c" * 64


def _result(*, is_free=True, document_key="doc-1", fact_document_key="doc-1"):
    published = datetime(2021, 7, 30, 11, 34, tzinfo=timezone.utc)
    available = datetime(2021, 8, 2, 1, 30, tzinfo=timezone.utc)
    return AdapterResult(
        policy=DataSourcePolicy(
            source_code="SOURCE",
            is_free=is_free,
            is_open_source=False,
            pit_capability="derived",
        ),
        batch=AdapterBatch(
            source_code="SOURCE",
            adapter_version="1.0.0",
            started_at=published,
            completed_at=available,
            request_parameters={},
            batch_hash=HASH_A,
        ),
        documents=[
            AdapterDocument(
                stable_key=document_key,
                document_type="half_year_report",
                title="Report",
                source_url="https://example.invalid/report",
                published_at=published,
                available_at=available,
                effective_date=date(2021, 6, 30),
                content_hash=HASH_B,
                publication_precision="minute",
                evidence_quality="derived_archive",
                metadata={},
            )
        ],
        facts=[
            AdapterFact(
                issuer_code="ISSUER",
                statement_type="income_statement",
                metric_code="revenue",
                period_start=date(2021, 1, 1),
                period_end=date(2021, 6, 30),
                value_numeric=100.0,
                value_text=None,
                unit="CNY",
                currency="CNY",
                published_at=published,
                available_at=available,
                revision_no=1,
                source_document_key=fact_document_key,
                source_fact_key="revenue",
                record_hash=HASH_C,
                metadata={},
            )
        ],
    )


def test_valid_free_adapter_result():
    validate_adapter_result(_result())


def test_paid_source_is_rejected():
    with pytest.raises(ValueError, match="paid"):
        validate_adapter_result(_result(is_free=False))


def test_unknown_document_reference_is_rejected():
    with pytest.raises(ValueError, match="unknown document"):
        validate_adapter_result(_result(fact_document_key="missing"))
