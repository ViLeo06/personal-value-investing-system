# Gate 0 native replay — Kweichow Moutai, 2021-08-30

## Status

This is the first **native V1.2** historical valuation chain. It is separate from the frozen legacy-workbook replay and is not tuned to reproduce the legacy value.

- Decision timestamp: `2021-08-30T15:00:00+08:00`
- Security: `600519.SH`
- Model: `moutai_owner_earnings_native@1.0.0`
- Valuation run: `3fadd6df-cad3-44a8-a7e9-8126673c87bc`
- PIT snapshot: `41c83d48-e114-47b1-93ae-b04c337d4273`
- Snapshot hash: `8263d23f6d581a3b96a219431efeba40c2b87774dc8a3ebf3a0437c1be4b328f`
- Input hash: `73e174fa57695eeaf2f36a12eeab7afaa85ac7d31927c0f155145e29becaaf89`
- Output hash: `98817cf2e591fa075812bf84984aad29ccc32dbca7af62d73515ca1a14be4bd3`

## Evidence and availability policy

The snapshot contains 13 PIT financial facts, five normalized facts, pre-cutoff source documents and one closing-price record. Eligibility is always:

```text
available_at <= decision_cutoff
```

The 2021 half-year disclosure was released after the Shanghai market close on 2021-07-30. Its facts are therefore assigned an earliest usable timestamp of `2021-08-02T09:30:00+08:00`, the next trading session, rather than being treated as available during the July 30 session.

Evidence references:

- 2020 annual report: `https://static.sse.com.cn/disclosure/listedinfo/announcement/c/new/2021-03-31/600519_20210331_1.pdf`
- 2021 half-year publication archive: `https://paper.cnstock.com/html/2021-07/31/content_1501967.htm`
- 2021 half-year numeric cross-check: `https://vip.stock.finance.sina.com.cn/corp/view/vCB_AllBulletinDetail.php?id=7409759&stockid=600519`
- Historical close cross-check: `https://www.jiemian.com/article/6896977.html`

The source-quality gate remains `provisional`: the official half-year filing binary and authoritative daily market-data file have not yet been preserved locally and hashed.

## Normalization

The deterministic normalization rule is `moutai_owner_earnings_normalization_v1`:

```text
inferred shares = 2020 parent net income / 2020 basic EPS
operating growth anchor = average(2021H1 revenue growth, 2021H1 parent-net-income growth)
normalized owner earnings/share = 2020 EPS × (1 + 2021H1 parent-net-income growth) × 95%
```

Results:

| Metric | Value |
|---|---:|
| Inferred weighted-average shares | 1,256,316,530.26 |
| 2021H1 revenue growth | 11.68% |
| 2021H1 parent-net-income growth | 9.08% |
| Growth anchor | 10.38% |
| Normalized owner earnings/share | CNY 38.5178 |
| 2020 OCF/net-income diagnostic | 1.1065x |
| 2021H1 OCF/net-income diagnostic | 0.8810x |

Interim OCF is diagnostic only because finance-subsidiary deposits and seasonal working-capital movements can distort cash conversion. The 5% maintenance-capital reserve is an explicit model policy, not a reported accounting fact.

## Scenario policy and results

All scenarios use 15 explicit years and start fading growth in year four toward terminal growth.

| Scenario | First-five-year growth | Discount rate | Terminal growth | Intrinsic value/share | 5Y economic IRR | 15% target buy price | Terminal-value share |
|---|---:|---:|---:|---:|---:|---:|---:|
| Pessimistic | 6.38% | 10.50% | 2.00% | CNY 603.07 | -15.66% | CNY 477.63 | 52.56% |
| Base | 10.38% | 9.50% | 2.50% | CNY 930.53 | -2.40% | CNY 744.47 | 46.39% |
| Optimistic | 13.38% | 8.50% | 3.00% | CNY 1,435.34 | 6.20% | CNY 1,172.97 | 39.32% |

At the observed CNY 1,586 close, Reverse DCF requires about **18.79%** annual owner-earnings growth for the first five years under the base discount and terminal assumptions.

Decision: `avoid_at_price`. Even the optimistic scenario is below the 15% five-year hurdle. Because evidence quality is provisional, the run is not eligible for automatic capital allocation under any scenario.

## Legacy reconciliation

The frozen legacy workbook reported a base intrinsic value of CNY 1,433.46. The native result is CNY 930.53, a difference of CNY -502.93 per share.

This is recorded as a reconciliation gap, not treated as a native-model failure and not closed by retuning. The main structural differences are:

- the native run uses a transparent normalization rule rather than an unrecoverable legacy starting-value/forecast bundle;
- the native run does not use an unpreserved timestamped broker-consensus archive;
- the native run applies a fixed maintenance-capital reserve and a published scenario policy;
- every input and output has a stable hash and lineage entry.

## Phase B outcome and attribution

The existing legacy corporate-action proxy ledger gives:

| Outcome | Value |
|---|---:|
| Start price | CNY 1,586.00 |
| End price | CNY 1,297.40 |
| Final share multiplier | 1.1566638x |
| Total shareholder return | -5.38% |
| Five-year annualized return | -1.10% |
| Benchmark proxy CAGR | 2.46% |
| Excess annualized return | -3.56 pp |

The no-buy decision was correct relative to the 15% hurdle. The native base-IRR forecast error was +1.30 percentage points, substantially smaller than the legacy base-IRR error of -5.66 points. Price-only return was -18.20%; proxy dividend reinvestment added about 12.82 percentage points cumulatively.

## Open quality gates

The following remain open and block a fully validated Gate 0 designation:

1. Preserve and hash the official 2021H1 filing binary.
2. Replace the provisional 2021-08-30 close with an authoritative daily market-data record.
3. Reconcile all nine dividend/corporate-action events with official records and actual ex-date reinvestment prices.
4. Load a fully adjusted daily total-return series and calculate maximum drawdown.
5. Either preserve a timestamped free broker-consensus archive or keep the native model explicitly disclosure-only.
6. Replace the fixed maintenance-capital reserve when a defensible company-specific estimate becomes available.

Until these gates close, the chain is **reproducible and decision-auditable, but data-provisional**.
