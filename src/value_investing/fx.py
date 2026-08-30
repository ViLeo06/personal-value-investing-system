"""Deterministic FX conversion with explicit rate orientation."""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite
from collections import deque
from typing import Iterable


@dataclass(frozen=True)
class FxRate:
    base_currency: str
    quote_currency: str
    rate: float

    def __post_init__(self) -> None:
        if not self.base_currency or not self.quote_currency:
            raise ValueError("FX currencies are required")
        if self.base_currency == self.quote_currency:
            raise ValueError("FX pair currencies must differ")
        if not isfinite(self.rate) or self.rate <= 0:
            raise ValueError("FX rate must be finite and positive")


@dataclass(frozen=True)
class FxConversion:
    source_currency: str
    target_currency: str
    source_amount: float
    target_amount: float
    effective_rate: float
    path: tuple[str, ...]


class FxBook:
    def __init__(self, rates: Iterable[FxRate]) -> None:
        self._graph: dict[str, list[tuple[str, float]]] = {}
        pair_keys: set[tuple[str, str]] = set()
        for rate in rates:
            key = (rate.base_currency, rate.quote_currency)
            if key in pair_keys or (key[1], key[0]) in pair_keys:
                raise ValueError(f"duplicate or conflicting FX pair: {key}")
            pair_keys.add(key)
            self._graph.setdefault(rate.base_currency, []).append(
                (rate.quote_currency, rate.rate)
            )
            self._graph.setdefault(rate.quote_currency, []).append(
                (rate.base_currency, 1.0 / rate.rate)
            )
        for currency in self._graph:
            self._graph[currency].sort(key=lambda item: item[0])

    def convert(
        self, amount: float, source_currency: str, target_currency: str
    ) -> FxConversion:
        if not isfinite(amount):
            raise ValueError("amount must be finite")
        if not source_currency or not target_currency:
            raise ValueError("source and target currencies are required")
        if source_currency == target_currency:
            return FxConversion(
                source_currency,
                target_currency,
                amount,
                amount,
                1.0,
                (source_currency,),
            )

        queue = deque([(source_currency, 1.0, (source_currency,))])
        visited = {source_currency}
        while queue:
            currency, effective_rate, path = queue.popleft()
            for next_currency, edge_rate in self._graph.get(currency, []):
                if next_currency in visited:
                    continue
                next_rate = effective_rate * edge_rate
                next_path = path + (next_currency,)
                if next_currency == target_currency:
                    return FxConversion(
                        source_currency=source_currency,
                        target_currency=target_currency,
                        source_amount=amount,
                        target_amount=amount * next_rate,
                        effective_rate=next_rate,
                        path=next_path,
                    )
                visited.add(next_currency)
                queue.append((next_currency, next_rate, next_path))
        raise LookupError(
            f"no FX conversion path from {source_currency} to {target_currency}"
        )
