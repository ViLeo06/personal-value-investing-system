# Gate 0 native replay: BYD 2021-08-30

## Status

**Provisional native V1.2 run.** This is a transparent manufacturing value-driver FCFF model built independently of the frozen legacy outputs. No parameter was reverse-engineered to reproduce the legacy valuation.

The run is not eligible for automatic capital allocation because the official filing bytes and authoritative 2021-08-30 market close have not yet been archived and hashed. The opening operating-margin anchor is also a disclosed profit-before-tax proxy rather than a fully reconstructed EBIT figure.

## Decision timestamp

- Issuer: BYD Company Limited
- Security: `002594.SZ`
- Decision timestamp: `2021-08-30T15:00:00+08:00`
- Frozen market-price proxy: CNY 281.97 from the legacy workbook
- Reporting and quote currency: RMB/CNY

## Contemporaneous operating anchors

The 2021 interim report disclosed:

- H1 revenue: RMB 90.8854 billion
- H1 parent net income: RMB 1.173571 billion
- H1 adjusted parent net income: RMB 0.368666 billion
- H1 operating cash flow: RMB 9.676845 billion
- Segment profit before tax: RMB 2.204115 billion
- Income-tax expense: RMB 0.393344 billion
- Capital expenditure: RMB 11.132530 billion
- Depreciation and amortization: RMB 6.395985 billion
- Cash and cash equivalents: RMB 21.152299 billion
- Interest-bearing debt proxy: RMB 41.273319 billion
- Minority interest: RMB 8.030113 billion
- Parent equity: RMB 81.255042 billion
- Shares outstanding: 2.861143 billion

Official filing reference:

`https://static.cninfo.com.cn/finalpage/2021-08-28/1210905306.PDF`

Readable mirror used for current extraction checks:

`https://money.finance.sina.com.cn/corp/view/vCB_AllBulletinDetail.php?id=7502467&stockid=002594`

Revenue is annualized by multiplying H1 by two. The starting operating margin is segment profit before tax divided by revenue, and the tax-rate proxy is income-tax expense divided by segment profit before tax. These approximations are deliberately visible and keep the data-quality status provisional.

## Model structure

1. Fifteen-year value-driver FCFF forecast.
2. Revenue growth, operating margin and RONIC are separate scenario paths and fade to stable-state values.
3. Reinvestment equals incremental NOPAT divided by RONIC.
4. Equity bridge adds cash and subtracts interest-bearing debt and minority interest.
5. The five-year holding value re-values the remaining FCFF and terminal value at year five; the opening equity bridge is held constant for this first policy version.
6. Reverse DCF scales the complete base growth path with one bounded multiplier. It is a market-expectations diagnostic, not a forecast.

## Frozen scenario results

| Scenario | Intrinsic value (CNY/share) | Year-5 value (CNY/share) | 5Y IRR | 15% target buy price | Terminal share of operating EV |
|---|---:|---:|---:|---:|---:|
| Pessimistic | -2.00 | 4.39 | -56.50% | 2.18 | 66.45% |
| Base | 25.96 | 77.74 | -22.72% | 38.65 | 123.42% |
| Optimistic | 111.99 | 219.31 | -4.90% | 109.04 | 103.72% |

Decision signal: `avoid_at_price` because even the optimistic five-year IRR is below the 15% hurdle.

## Why terminal value can exceed 100% of enterprise value

The base and optimistic cases require large reinvestment during the explicit growth period. Their present value of explicit FCFF is negative, while the later stable-state business has positive value. Therefore:

`enterprise value = negative explicit-period PV + positive terminal-value PV`

The terminal-value PV can mathematically exceed total enterprise value. This is not hidden or clipped; it is a warning that the valuation depends heavily on successful long-run conversion of growth investment into mature cash flow.

## Reverse DCF

At the base margin, RONIC, WACC and bridge assumptions, matching CNY 281.97 requires:

- uniform explicit-growth-path multiplier: about `3.1830x`
- implied first-year revenue growth: about `95.49%`

This is economically extreme and should be read as evidence that the 2021 price embedded much stronger operating expectations than the native base case, not as a literal recommendation to forecast 95.49% revenue growth.

## Legacy reconciliation

- Frozen legacy base value: CNY 22.78 per share
- Native V1.2 base value: CNY 25.96 per share
- Native minus legacy: approximately CNY +3.18 per share

The proximity is incidental. The native model is independently parameterized and the difference is retained.

## Open evidence gates

- archive and hash the official interim filing bytes;
- replace the legacy-workbook close with an authoritative exchange market file;
- reconstruct EBIT and the operating/non-operating bridge from archived statement notes;
- model the future cash, debt and minority-interest bridge instead of holding it constant;
- load the native run, assumptions, outputs, reverse solve and lineage into Supabase only after repository CI passes.
