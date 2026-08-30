"""Allocate issuer equity value across share classes and quote currencies."""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite
from typing import Iterable

from .fx import FxBook


@dataclass(frozen=True)
class ShareClassClaim:
    security_code: str
    share_class_code: str
    shares_outstanding: float
    economic_rights_multiplier: float
    quote_currency: str

    @property
    def equivalent_shares(self) -> float:
        return self.shares_outstanding * self.economic_rights_multiplier


@dataclass(frozen=True)
class ShareClassValue:
    security_code: str
    share_class_code: str
    issuer_reporting_currency: str
    quote_currency: str
    value_per_share_reporting_currency: float
    value_per_share_quote_currency: float
    economic_rights_multiplier: float
    shares_outstanding: float


def allocate_issuer_equity_value(
    issuer_equity_value: float,
    issuer_reporting_currency: str,
    claims: Iterable[ShareClassClaim],
    fx_book: FxBook,
) -> tuple[ShareClassValue, ...]:
    if not isfinite(issuer_equity_value) or issuer_equity_value < 0:
        raise ValueError("issuer equity value must be finite and non-negative")
    if not issuer_reporting_currency:
        raise ValueError("issuer reporting currency is required")
    claim_rows = tuple(claims)
    if not claim_rows:
        raise ValueError("at least one share class is required")
    codes = [claim.security_code for claim in claim_rows]
    if len(codes) != len(set(codes)):
        raise ValueError("security codes must be unique")
    for claim in claim_rows:
        if not claim.security_code or not claim.share_class_code or not claim.quote_currency:
            raise ValueError("security, share-class and currency identifiers are required")
        if not isfinite(claim.shares_outstanding) or claim.shares_outstanding < 0:
            raise ValueError("shares outstanding must be finite and non-negative")
        if (
            not isfinite(claim.economic_rights_multiplier)
            or claim.economic_rights_multiplier <= 0
        ):
            raise ValueError("economic-rights multiplier must be finite and positive")
    total_equivalent_shares = sum(claim.equivalent_shares for claim in claim_rows)
    if total_equivalent_shares <= 0:
        raise ValueError("total equivalent shares must be positive")
    base_value_per_equivalent_share = issuer_equity_value / total_equivalent_shares

    results: list[ShareClassValue] = []
    for claim in sorted(claim_rows, key=lambda row: row.security_code):
        reporting_value = (
            base_value_per_equivalent_share * claim.economic_rights_multiplier
        )
        converted = fx_book.convert(
            reporting_value,
            issuer_reporting_currency,
            claim.quote_currency,
        )
        results.append(
            ShareClassValue(
                security_code=claim.security_code,
                share_class_code=claim.share_class_code,
                issuer_reporting_currency=issuer_reporting_currency,
                quote_currency=claim.quote_currency,
                value_per_share_reporting_currency=reporting_value,
                value_per_share_quote_currency=converted.target_amount,
                economic_rights_multiplier=claim.economic_rights_multiplier,
                shares_outstanding=claim.shares_outstanding,
            )
        )
    return tuple(results)
