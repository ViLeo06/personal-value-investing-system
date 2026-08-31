# Gate 0 native replay: Tencent 2021-08-30

## Status

**Provisional native V1.2 run.** This is not the frozen legacy workbook and its assumptions were not tuned to reproduce the legacy value. It uses the shared value-driver FCFF engine, a transparent SOTP bridge and the shared five-year holding-value calculation.

The run is not eligible for automatic capital allocation because the filing bytes, authoritative 2021-08-30 market close and authoritative historical CNY/HKD fixing have not yet been archived and hashed.

## Decision timestamp

- Issuer: Tencent Holdings Limited
- Security: `0700.HK`
- Decision timestamp: `2021-08-30T16:00:00+08:00`
- Frozen market-price proxy: HKD 465.80 from the legacy workbook
- Reporting currency: RMB
- Quote currency: HKD
- FX proxy: 1 RMB = 1.2042 HKD

## Contemporaneous operating anchors

Tencent's 2021 interim announcement reported:

- H1 revenue: RMB 273.562 billion
- H1 non-IFRS operating profit: RMB 85.6 billion
- H1 IFRS profit attributable to equity holders: RMB 90.354 billion
- Basic EPS: RMB 9.492
- Total cash: RMB 255.2 billion
- Net debt: RMB 21.0 billion
- Fair value of listed investee stakes: RMB 1,446 billion
- Q2 segment revenue: VAS RMB 72.0 billion; online advertising RMB 22.8 billion; FinTech and business services RMB 41.9 billion

Disclosure reference:

`https://www.prnewswire.com/news-releases/tencent-announces-2021-second-quarter-and-interim-results-301357768.html`

The annualized revenue anchor is H1 revenue multiplied by two. The operating-margin anchor is H1 non-IFRS operating profit divided by H1 revenue. Weighted-average shares are inferred from attributable profit divided by basic EPS. These are explicit normalization choices, not raw accounting facts.

## Model structure

1. Fifteen-year value-driver FCFF forecast.
2. Revenue growth, operating margin and RONIC are modeled independently and fade toward stable-state values.
3. Listed investments are added through SOTP after a scenario-specific holding-company/liquidity discount.
4. Net debt is subtracted.
5. RMB value per share is translated to HKD using the frozen FX proxy.
6. The five-year holding value uses the remaining FCFF and terminal value at year five. The SOTP bridge and FX rate are held constant for this first policy version.
7. Reverse DCF scales the complete base explicit growth path with one bounded multiplier. It is a diagnostic, not a forecast.

## Frozen scenario results

| Scenario | Intrinsic value (HKD/share) | Year-5 value (HKD/share) | 5Y IRR | 15% target buy price | Terminal share of operating EV |
|---|---:|---:|---:|---:|---:|
| Pessimistic | 247.17 | 265.59 | -10.63% | 132.05 | 27.18% |
| Base | 377.83 | 447.33 | -0.81% | 222.40 | 40.55% |
| Optimistic | 560.03 | 695.17 | 8.34% | 345.62 | 52.64% |

Decision signal: `avoid_at_price` because even the optimistic five-year IRR is below the 15% hurdle.

## Reverse DCF

At the base margin, RONIC, WACC, investment discount and stable-state assumptions, matching HKD 465.80 requires:

- uniform explicit-growth-path multiplier: about `1.5525x`
- implied first-year revenue growth: about `20.18%`

This does not mean that every forecast year must grow at 20.18%. The multiplier applies to the complete fading base growth path and is recorded only as a market-expectations diagnostic.

## Legacy reconciliation

- Frozen legacy base value: HKD 588.31 per share
- Native V1.2 base value: HKD 377.83 per share
- Native minus legacy: approximately HKD -210.48 per share

The difference is preserved rather than removed. The native model explicitly discounts listed investments and charges reinvestment through incremental NOPAT/RONIC; the legacy workbook's full parameter set is unavailable.

## Open evidence gates

- archive and hash the official interim filing bytes;
- replace the legacy-workbook close with an authoritative HKEX market file;
- replace the secondary FX proxy with an authoritative historical fixing;
- model the future SOTP bridge and FX path instead of holding them constant;
- load the native run, assumptions, outputs, reverse solve and lineage into Supabase only after repository CI passes.
