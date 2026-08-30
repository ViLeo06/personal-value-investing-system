"""Versioned financial-statement parser contracts."""

from .base import (
    FactKind,
    FinancialStatementParser,
    ParsedFact,
    ParserResult,
)

__all__ = [
    "FactKind",
    "FinancialStatementParser",
    "ParsedFact",
    "ParserResult",
]
