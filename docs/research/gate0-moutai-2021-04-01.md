# Gate 0 prototype — Kweichow Moutai — 2021-04-01

## Purpose

First machine-recorded PIT evidence snapshot. This is **not yet a full valuation/backtest decision**; it validates the evidence → PIT fact → snapshot chain before porting valuation logic.

## Decision cutoff

`2021-04-01T00:00:00+08:00`

Eligibility rule: `available_at <= decision cutoff`.

## Evidence

- Issuer: `KWEICHOW_MOUTAI`
- Security: `600519.SH`
- Report: 贵州茅台2020年年度报告
- Official evidence URL: `https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2021-03-31/600519_20210331_1.pdf`
- Publication date: 2021-03-31

Exact exchange release time has not yet been captured. The database records this as a data-quality warning; therefore the prototype cutoff is placed after the full publication date rather than pretending to know intraday availability.

## Seeded FY2020 facts

- Revenue: CNY 94,915,380,916.72
- Net income attributable to parent: CNY 46,697,285,429.81
- Operating cash flow: CNY 51,669,068,693.03
- Total assets: CNY 213,395,810,527.46
- Equity attributable to parent: CNY 161,322,735,087.56
- Basic EPS: CNY 37.17/share

## Snapshot

- cutoff policy: `pit_cutoff_v1`
- snapshot hash: `9950df576f62d3a87aac8b7ee276a173`
- eligible financial facts: 6
- PIT leakage smoke test: 0 leaked rows

## Remaining work before this becomes a full decision replay

1. Capture exact official release timestamp or establish a conservative market-open availability policy.
2. Load unadjusted market price for the decision date from an approved source.
3. Load dividend/corporate-action history required for total return.
4. Normalize the full Owner Earnings input set.
5. Run the versioned valuation engine and freeze assumptions/output hashes.
6. Reveal future outcome only after the Phase-A decision snapshot is frozen.
