# Total-return accounting contract

The backtest authority uses **unadjusted market prices plus explicit corporate-action events**. Adjusted price series may be used only as a secondary reconciliation source.

## Event rules

1. A daily close becomes eligible only after the configured exchange-close safety lag.
2. A cash dividend is recognized as a receivable on the ex-date so the price drop does not create an artificial loss.
3. The receivable converts to cash on the payment date.
4. A split or bonus issue changes quantity on its effective date; it must not create economic profit or loss by itself.
5. Rights issues, scrip elections, spin-offs, mergers, delistings and code changes require dedicated event handlers before the affected security is admitted to a formal backtest.
6. A/H share classes are separate securities and may have different prices, currencies and corporate-action mechanics, while sharing the same issuer-level fundamentals.

## Reconciliation

For each security and cohort, the system should compare:

- event-ledger total return;
- a trusted total-return index or independently adjusted series where available;
- cash-dividend sum and split factors;
- start/end unadjusted prices.

Any material difference is recorded in `audit.data_quality_issues`; it is never hidden by changing the valuation assumptions.
