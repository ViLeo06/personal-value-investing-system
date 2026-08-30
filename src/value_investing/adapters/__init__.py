"""Thin source adapters; domain modules never import supplier field names."""

from .base import (
    AdapterBatch,
    AdapterDocument,
    AdapterFact,
    AdapterResult,
    DataSourcePolicy,
    validate_adapter_result,
)

__all__ = [
    "AdapterBatch",
    "AdapterDocument",
    "AdapterFact",
    "AdapterResult",
    "DataSourcePolicy",
    "validate_adapter_result",
]
