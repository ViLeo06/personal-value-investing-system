# Gate 0 — Kweichow Moutai prototype valuation

## Purpose

This run proves that one historical valuation can be reconstructed from a frozen point-in-time evidence set, normalized with explicit lineage, valued by a deterministic model version, and reproduced from committed seeds.

It is **not an investment recommendation** and must not be interpreted as a completed 2021 decision.

## Historical cutoff

- Issuer: `KWEICHOW_MOUTAI`
- Security: `600519.SH`
- Decision cutoff: `2021-04-01T00:00:00+08:00`
- Snapshot logical hash: `9950df576f62d3a87aac8b7ee276a173`
- Snapshot membership hash: calculated from stable business keys under `stable_input_key_v1`

The snapshot freezes one annual-report evidence record and six 2020 financial facts. Every frozen row must satisfy `source_available_at <= decision cutoff`.

## Frozen facts

| Metric | 2020 value | Unit |
|---|---:|---|
| Revenue | 94,915,380,916.72 | CNY |
| Net income attributable to parent | 46,697,285,429.81 | CNY |
| Operating cash flow | 51,669,068,693.03 | CNY |
| Total assets | 213,395,810,527.46 | CNY |
| Equity attributable to parent | 161,322,735,087.56 | CNY |
| Basic EPS | 37.17 | CNY/share |

## Gate-0 normalization

Until maintenance capital expenditure is separately available, the prototype uses:

```text
owner earnings proxy = min(parent net income, operating cash flow)
shares proxy          = parent net income / basic EPS
owner earnings/share  = owner earnings proxy / shares proxy
```

This is conservative and reproducible, but it is not the final Owner Earnings definition. The open quality issue `OE_PROXY_MISSING_MAINTENANCE_CAPEX` blocks investment-ready status.

## Model version

- Model: `owner_earnings_dcf`
- Version: `0.1.0-gate0`
- Explicit forecast: 10 years
- Stage 1: years 1–5
- Fade: years 6–10, linearly converging to terminal growth
- Terminal method: Gordon growth
- Investor hurdle: 15%, kept separate from company discount rate

Forward valuation and Reverse DCF use the same forecast and terminal-value functions. Reverse DCF changes only the solved variable.

## Prototype scenarios

| Scenario | Probability | Stage-1 growth | Discount rate | Terminal growth |
|---|---:|---:|---:|---:|
| Pessimistic | 25% | 6.0% | 10.5% | 2.5% |
| Base | 50% | 10.0% | 9.0% | 3.0% |
| Optimistic | 25% | 13.0% | 8.0% | 3.5% |

These parameters are an engineering test envelope. They are tagged `prototype_not_investment_ready` and must later be replaced by historically calibrated base rates and company-specific evidence.

## Outputs persisted

For each scenario the run stores:

- year 1, year 5 and year 10 owner earnings;
- present value of the explicit period;
- present value of terminal value;
- total equity value;
- intrinsic value per share;
- terminal-value share;
- value and per-share price at the 15% investor hurdle.

A probability-weighted summary is stored only as a reporting convenience; individual scenario results remain authoritative.

## Quality gates still open

1. Exact unadjusted market close at the decision timestamp.
2. Reverse DCF and market-implied expectations.
3. Maintenance versus growth capital expenditure.
4. Full historical financial and restatement chain.
5. Dividend and corporate-action ledger through the five-year outcome date.
6. Exact official report binary archive and byte hash.
7. Reconciliation against the V1.1 Excel workbook.

Until these gates close, the run status remains `completed_prototype`, not `investment_ready`.
