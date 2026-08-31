from __future__ import annotations

from dataclasses import dataclass
from math import isclose
from typing import Any, Mapping


@dataclass(frozen=True, slots=True)
class GoldenDifference:
    key: str
    expected: Any
    actual: Any
    reason: str


def compare_golden_values(
    baseline: Mapping[str, Any],
    actual: Mapping[str, Any],
    *,
    relative_tolerance: float = 1e-9,
    absolute_tolerance: float = 1e-6,
) -> tuple[GoldenDifference, ...]:
    differences: list[GoldenDifference] = []
    baseline_cells = baseline.get("cells")
    if not isinstance(baseline_cells, Mapping):
        raise ValueError("baseline must contain a 'cells' mapping")
    for key, specification in baseline_cells.items():
        if key not in actual:
            differences.append(
                GoldenDifference(key, specification.get("cached_value"), None, "missing actual value")
            )
            continue
        expected = specification.get("cached_value")
        observed = actual[key]
        if isinstance(expected, (int, float)) and isinstance(observed, (int, float)):
            if not isclose(
                float(expected),
                float(observed),
                rel_tol=relative_tolerance,
                abs_tol=absolute_tolerance,
            ):
                differences.append(
                    GoldenDifference(key, expected, observed, "numeric value outside tolerance")
                )
        elif expected != observed:
            differences.append(GoldenDifference(key, expected, observed, "value mismatch"))
    unexpected = sorted(set(actual) - set(baseline_cells))
    for key in unexpected:
        differences.append(GoldenDifference(key, None, actual[key], "unexpected actual value"))
    return tuple(differences)
