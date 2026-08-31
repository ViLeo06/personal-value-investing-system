import json
from pathlib import Path
import subprocess
import sys

from openpyxl import Workbook

from value_investing.golden import compare_golden_values


def test_excel_extractor_and_comparator(tmp_path: Path) -> None:
    workbook_path = tmp_path / "model.xlsx"
    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "Case"
    sheet["A1"] = 100.0
    sheet["A2"] = "=A1*2"
    workbook.save(workbook_path)

    config_path = tmp_path / "cells.json"
    config_path.write_text(
        json.dumps(
            {
                "cells": [
                    {"key": "base_value", "sheet": "Case", "cell": "A1", "unit": "CNY"},
                    {"key": "double_value", "sheet": "Case", "cell": "A2", "unit": "CNY"},
                ]
            }
        ),
        encoding="utf-8",
    )
    output_path = tmp_path / "baseline.json"
    subprocess.run(
        [
            sys.executable,
            "scripts/extract_excel_golden.py",
            str(workbook_path),
            str(config_path),
            str(output_path),
        ],
        check=True,
    )
    baseline = json.loads(output_path.read_text(encoding="utf-8"))
    assert baseline["workbook_sha256"]
    assert baseline["cells"]["base_value"]["cached_value"] == 100.0
    assert baseline["cells"]["double_value"]["formula_or_literal"] == "=A1*2"

    # openpyxl does not calculate formulas, so the cached formula value is None.
    differences = compare_golden_values(
        baseline,
        {"base_value": 100.0, "double_value": None},
    )
    assert differences == ()


def test_comparator_reports_numeric_drift() -> None:
    baseline = {"cells": {"value": {"cached_value": 100.0}}}
    differences = compare_golden_values(baseline, {"value": 101.0})
    assert differences[0].reason == "numeric value outside tolerance"
