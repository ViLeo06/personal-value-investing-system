# Model-family metric contracts

## Purpose

Valuation modules consume canonical metrics. Exchange, filing, provider and parser field names must be mapped into these contracts before valuation code sees them.

Every observation must carry:

- `metric_code`;
- period and statement scope;
- numeric/text value, unit, currency and scale;
- `published_at`, `available_at` and `ingested_at`;
- source document and parser/normalization version;
- record/content hash;
- evidence tier.

A metric available after a historical cutoff cannot replace the version that was actually visible at the cutoff.

## Evidence tiers

| Tier | Meaning | Readiness effect |
|---|---|---|
| `official_binary` | Exact official filing/announcement bytes retained and hashed | Eligible for validated runs |
| `official_html` | Official exchange/issuer page retained with publication time | Eligible for validated runs when content is stable and hashed |
| `derived_official` | Deterministic calculation from official facts with lineage | Eligible for validated runs |
| `open_source_cross_check` | Free/open adapter used as a cross-check | Provisional if it is the only evidence |
| `aggregator` | Third-party aggregation or republished data | Provisional |
| `manual_proxy` | Manually entered proxy or approximation | Provisional |

Missing required metrics or incompatible units block the run. Required observations without hashes, or observations supported only by cross-checks/proxies, make the run provisional.

## High-moat consumer: `owner_earnings_dcf`

Required canonical inputs:

- `revenue`;
- `net_income_parent`;
- `operating_cash_flow`;
- `maintenance_capex`;
- `shares_outstanding`.

Core derivations include owner earnings, owner earnings per share, cash conversion and a PIT growth anchor. `maintenance_capex` must be a versioned normalization with an explicit policy; it may not be hidden inside a spreadsheet formula.

## Platform technology: `fcff_sotp`

Required canonical inputs:

- `revenue`;
- `ebit`;
- `tax_rate_normalized`;
- `sales_to_capital`;
- `non_operating_assets`;
- `net_debt`;
- `shares_outstanding`.

Operating FCFF and non-operating assets are valued separately. Segment facts use canonical codes such as `segment_revenue` and `segment_operating_profit`, with the segment identifier in metadata. Investment holdings must not be silently included in operating margins or FCFF.

## Capital-intensive manufacturing: `value_driver_fcff`

Required canonical inputs:

- `nopat`;
- `ronic`;
- `net_debt`;
- `shares_outstanding`.

The model enforces:

`growth = reinvestment_rate × RONIC`

Supporting normalization normally includes revenue, EBIT, normalized tax, invested capital, capital expenditure, depreciation/amortization and working-capital change. A growth path that implies reinvestment above 100% is invalid unless a separately documented financing/capacity model explains it.

## Bank: `residual_income`

Required canonical inputs:

- `book_value_per_share`;
- `roe`;
- `payout_ratio`;
- `cost_of_equity`.

Supporting drivers include gross loans, customer deposits, net interest margin, credit cost, NPL ratio, provision coverage, CET1 and risk-weighted assets. The bank model rolls book value forward and values residual income; FCFF is not the primary method.

## Units and currencies

- Ratios are decimal values: 15% is stored as `0.15`.
- Monetary statement facts retain original currency and scale; normalization converts scale explicitly.
- Per-share values use `CNY/share`, `HKD/share`, `USD/share` or the generic `currency/share` contract.
- Share counts use `shares`, never monetary units.
- A/H securities remain distinct. Issuer-level operations may be common, while price, currency, shares, corporate actions and investor return remain security-level.

## Version discipline

A change in a mapping or normalization policy creates a new normalization/model version. Frozen Phase A runs are never overwritten. Corrections are represented as later revisions with their own `available_at` and lineage.
