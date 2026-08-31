#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
from hashlib import sha256
import json
from pathlib import Path
from typing import Any

from openpyxl import load_workbook


@dataclass(frozen=True, slots=True)
class CellSpec:
    key: str
    sheet: str
    cell: str
    unit: str | None = None


def file_sha256(path: Path) -> str:
    digest = sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_specs(config_path: Path) -> list[CellSpec]:
    config = json.loads(config_path.read_text(encoding="utf-8"))
    cells = config.get("cells")
    if not isinstance(cells, list) or not cells:
        raise ValueError("Config must contain a non-empty 'cells' array")
    specs: list[CellSpec] = []
    for item in cells:
        specs.append(
            CellSpec(
                key=str(item["key"]),
                sheet=str(item["sheet"]),
                cell=str(item["cell"]),
                unit=None if item.get("unit") is None else str(item["unit"]),
            )
        )
    if len({spec.key for spec in specs}) != len(specs):
        raise ValueError("Golden keys must be unique")
    return specs


def extract(workbook_path: Path, specs: list[CellSpec]) -> dict[str, Any]:
    formula_book = load_workbook(workbook_path, data_only=False, read_only=True)
    value_book = load_workbook(workbook_path, data_only=True, read_only=True)
    try:
        output: dict[str, Any] = {
            "workbook": workbook_path.name,
            "workbook_sha256": file_sha256(workbook_path),
            "sheets": formula_book.sheetnames,
            "cells": {},
        }
        for spec in specs:
            if spec.sheet not in formula_book.sheetnames:
                raise KeyError(f"Missing sheet: {spec.sheet}")
            formula_value = formula_book[spec.sheet][spec.cell].value
            cached_value = value_book[spec.sheet][spec.cell].value
            output["cells"][spec.key] = {
                "sheet": spec.sheet,
                "cell": spec.cell,
                "formula_or_literal": formula_value,
                "cached_value": cached_value,
                "unit": spec.unit,
            }
        canonical = json.dumps(
            output, ensure_ascii=False, sort_keys=True, separators=(",", ":"), default=str
        ).encode("utf-8")
        output["baseline_sha256"] = sha256(canonical).hexdigest()
        return output
    finally:
        formula_book.close()
        value_book.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("workbook", type=Path)
    parser.add_argument("config", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    specs = load_specs(args.config)
    baseline = extract(args.workbook, specs)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(baseline, ensure_ascii=False, indent=2, sort_keys=True, default=str),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
