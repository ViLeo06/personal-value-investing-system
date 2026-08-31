# Moutai Gate 0 Owner Earnings policy

This policy is frozen before the formal 2021-04-01 valuation is completed. It prevents later data selection from being adjusted to produce a preferred valuation.

## Owner Earnings bridge

`Owner Earnings = net income attributable to parent + D&A + other non-cash adjustments - maintenance capex - incremental operating working capital`

All amounts are consolidated, attributable to the same fiscal period, and eligible under the historical decision cutoff.

## Net income

Use audited consolidated net income attributable to shareholders of the parent. Minority interest is not included in the numerator used for common-share valuation.

## Depreciation and amortization

Include audited depreciation of property, plant and equipment, amortization of intangible assets and amortization of long-term deferred expenses where they are non-cash expenses already deducted in net income. Do not double-count amounts already embedded in another non-cash adjustment.

## Other non-cash adjustments

Only individually identified, source-backed non-cash items may enter this line. Changes in provisions, impairments and fair-value items require item-level review. A residual plug is forbidden.

## Maintenance capex

Maintenance capex is the capital spending required to preserve the current productive and distribution capacity in real terms.

For Gate 0:

1. Start from cash paid to acquire or construct fixed assets, intangible assets and other long-term assets.
2. Classify projects using official annual-report project descriptions and construction-in-progress notes.
3. Explicit expansion, new-capacity and strategic growth projects are excluded from maintenance capex and retained as growth investment.
4. Replacement, safety, environmental compliance, routine technical renovation and sustaining infrastructure are included.
5. If project-level classification is incomplete, use the conservative upper bound of total qualifying capex and keep the formal valuation in sensitivity mode; do not silently adopt depreciation as maintenance capex.

## Incremental operating working capital

Use operating, non-interest-bearing working capital. Include inventories, trade receivables and other operating receivables; subtract trade payables, contract liabilities/advances and other operating payables. Exclude cash, financial investments, interest-bearing debt, taxes payable and financing balances unless a documented industry-specific exception applies.

The cash use is `NWC_t - NWC_(t-1)`. A positive change reduces Owner Earnings.

## Shares outstanding

Use point-in-time common shares outstanding at the decision cutoff, reconciled to audited share capital and any corporate actions already effective. Do not use a current share count or a rounded `net income / EPS` estimate in the formal run.

## Net cash

Use cash and cash equivalents plus liquid financial investments that are demonstrably non-operating and available to common shareholders, less interest-bearing debt and debt-like obligations. Restricted cash, customer advances and operating float are excluded. The convention and every included account are persisted in the run assumptions.

## Evidence gate

Each formal input requires one of:

- official primary evidence with a content hash; or
- two independent sources, one of which is an official exchange/disclosure source.

A single derived provider may support engineering proxies but cannot release the formal run from `blocked_data`.
