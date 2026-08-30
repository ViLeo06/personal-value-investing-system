from value_investing.gate0_report import build_gate0_report


def test_gate0_report_is_deterministic_and_complete():
    report = build_gate0_report()
    assert report["report_hash"] == (
        "a76b813d9a2f3fd092a8b84d21ff62109f6e620892cb8f3065004e94f76376f9"
    )
    assert len(report["rows"]) == 4
    assert {row["issuer_code"] for row in report["rows"]} == {
        "KWEICHOW_MOUTAI",
        "TENCENT",
        "BYD",
        "CMB",
    }
    assert all(row["hurdle_classification_correct"] for row in report["rows"])
