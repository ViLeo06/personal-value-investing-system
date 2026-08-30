# Gate 0 native replay — China Merchants Bank, 2021-08-30

## Status

This is the first **native V1.2 bank residual-income chain**. It is separate from the frozen legacy-workbook replay and is not tuned to reproduce the legacy valuation.

- Decision timestamp: `2021-08-30T15:00:00+08:00`
- Security: `600036.SH`
- Model: `cmb_residual_income_native@1.0.0`
- Current price used by the run: CNY 48.45
- Input hash: `58d83f6292e59197fc4effb2bc3f98cd28c80cc4af1cf7af67d20a1b254fc683`
- Output hash: `6d14a8ce6b78384daa466a7e673c3ecd4c73d487198856e19d8346af24ed2104`

The chain is reproducible and decision-auditable, but remains **data-provisional** because the official report binary and authoritative historical daily market file have not yet been retained and hashed in the evidence store.

## Contemporaneous evidence

Official 2021 half-year filing reference:

- `https://static.cninfo.com.cn/finalpage/2021-08-14/1210747886.PDF`

The filing reported, among other items:

| Metric | 2021H1 value |
|---|---:|
| Revenue | CNY 168.749bn |
| Net income attributable to bank shareholders | CNY 61.150bn |
| Basic EPS attributable to ordinary shareholders | CNY 2.35 |
| Book value per ordinary share | CNY 26.60 |
| Annualized ROE attributable to ordinary shareholders | 18.06% |
| Net interest margin | 2.49% |
| Credit cost | 0.56% |
| Cost-income ratio | 27.95% |
| Non-performing-loan ratio | 1.01% |
| Common-equity Tier-1 ratio | 11.89% |

The filing date was a Saturday. Under `availability_policy_v1`, the earliest usable timestamp is the next Shanghai trading session: `2021-08-16T09:30:00+08:00`.

## Normalization

The deterministic rule is `cmb_residual_income_normalization_v1`.

- Opening common book value is the reported CNY 26.60 per share.
- Reported annualized ROE of 18.06% is an operating-quality anchor, not a permanent forecast.
- Half-year EPS is annualized to CNY 4.70 only as a diagnostic.
- NIM, credit cost, cost-income ratio, NPL ratio and CET1 are diagnostics used to judge whether the ROE path is economically plausible.
- Scenario ROE, payout and cost-of-equity paths are explicit policy assumptions and are never hidden inside an exit P/B multiple.

## Scenario policy and results

All scenarios use ten explicit years. Book value rolls forward from earnings less dividends; value equals current common book value plus discounted residual income. The five-year investor return includes modeled dividends and the year-five value of all remaining residual income.

| Scenario | Initial/final explicit ROE | Payout | Cost of equity | Terminal ROE | Terminal growth | Intrinsic value/share | 5Y economic IRR | 15% target buy price |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Pessimistic | 14.50% → 8.00% | 40% | 12.00% | 9.50% | 2.00% | CNY 20.70 | -7.20% | CNY 18.44 |
| Base | 17.00% → 10.50% | 35% | 10.50% | 11.50% | 3.00% | CNY 36.14 | 3.76% | CNY 30.07 |
| Optimistic | 18.00% → 13.50% | 32% | 9.50% | 12.50% | 3.50% | CNY 57.68 | 13.60% | CNY 45.72 |

Decision: `avoid_at_price`. Even the optimistic scenario is below the 15% five-year hurdle, and the evidence quality is provisional.

## Market-implied expectations

At CNY 48.45, the base cost-of-equity, payout and terminal assumptions imply a uniform explicit-period ROE of approximately **17.67%**.

In plain language, the 2021 price required CMB to preserve almost all of its reported 18.06% annualized ROE for a long period. The investment case therefore depended on persistent high profitability, not merely on a superficially low earnings multiple.

## Legacy reconciliation

The frozen legacy workbook reported:

- base intrinsic value: CNY 40.30;
- base five-year IRR: 5.78%;
- 15% target buy price: CNY 32.74;
- reverse long-run ROE: 14.10%.

The native base value is CNY 36.14, or CNY 4.16 below the legacy value. This difference is preserved rather than removed by retuning. The native model uses a fully explicit ten-year ROE/payout path and calculates the year-five exit value from the same residual-income engine; the legacy workbook does not expose a complete executable historical assumption bundle.

## Phase B proxy outcome

The existing legacy corporate-action proxy ledger reports:

- realized five-year total-shareholder-return CAGR: 0.62%;
- benchmark proxy CAGR: 2.46%;
- excess CAGR: -1.84 percentage points.

Against that provisional outcome, the native base IRR forecast error is approximately -3.13 percentage points (`realized CAGR - predicted base IRR`). The 15% hurdle correctly rejected the 2021 entry price.

## Open quality gates

1. Retain and hash the exact official 2021H1 PDF bytes.
2. Replace the workbook-derived CNY 48.45 close with an authoritative daily market-data record.
3. Reconcile every 2021–2026 dividend using official ex-date, payment-date and reinvestment-price evidence.
4. Load the full daily total-return series and calculate drawdown.
5. Add at least two more historical CMB decision snapshots before interpreting model performance.
6. Replace policy-only payout and cost-of-equity paths with versioned empirical priors when a free, reproducible historical dataset is available.
