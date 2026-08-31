# Gate 0 acceptance checklist

Gate 0 validates mechanics and replay trustworthiness. It does not establish strategy alpha.

## A. Fixed validation matrix

| Company | Model family | Snapshot 1 | Snapshot 2 | Snapshot 3 |
|---|---|---|---|---|
| Kweichow Moutai | Owner Earnings DCF | required | required | required |
| Tencent | FCFF + SOTP | required | required | required |
| BYD | value-driver FCFF | required | required | required |
| China Merchants Bank | residual income | required | required | required |

A case is counted only when the formal run is completed, content-hashed, evidence-qualified and Golden-Test reconciled.

## B. Per-case acceptance

- [ ] Decision cutoff is timezone-aware and exchange-calendar aligned.
- [ ] Issuer and security/share class are unambiguous.
- [ ] Snapshot hash is generated from canonical content, not database IDs.
- [ ] Publication and availability timestamps are present for every input fact.
- [ ] Latest eligible historical revision is selected without look-ahead.
- [ ] Required formal inputs are non-null, unit-consistent and evidence-qualified.
- [ ] Forward valuation and Reverse DCF share the same valuation function.
- [ ] Bear/base/bull assumptions form coherent operating paths.
- [ ] Decision-reference price is observable at the cutoff.
- [ ] Execution price occurs strictly after the decision cutoff.
- [ ] Company actions use official effective/ex/record/payment dates.
- [ ] Run assumptions, lineage, input hash and output hash are frozen.
- [ ] V1.1 Excel Golden Test passes within the configured tolerance.

## C. Per-holding-period acceptance

- [ ] Unadjusted daily prices cover the complete holding window.
- [ ] Cash dividends, splits, rights, distributions, code changes and delisting events are represented explicitly.
- [ ] Daily NAV equals positions plus cash/receivables.
- [ ] Buy and sell transactions reconcile to performance start/end values.
- [ ] Total return recalculates from price effect, income effect, fees and other actions.
- [ ] Maximum drawdown recalculates from the daily total-return path.
- [ ] Benchmark uses a compatible total-return and currency convention.
- [ ] Attribution sums to total return within tolerance.
- [ ] Result hash is reproducible from stored output metrics.

## D. Cross-case acceptance

- [ ] Exactly twelve formal cases are present.
- [ ] All four model families are exercised.
- [ ] No company has fewer than three accepted historical snapshots.
- [ ] Survivorship-biased exclusions are documented and tested.
- [ ] Non-overlapping five-year cohorts are reported separately from overlapping windows.
- [ ] Simple value/quality baselines are available for later Gate 2 comparisons.

## E. Machine-readable controls

```sql
select * from audit.gate0_status();
select * from audit.gate0_overall();
select * from audit.gate_evidence_requirement_status('GATE0');
select * from audit.proxy_backtest_integrity(
  'bf724082-e2b9-4531-a61a-64a2b0c4e501'::uuid
);
```

A missing row is never a pass. `audit.gate0_status()` joins a fixed check catalog and therefore returns every enabled check even when the underlying data are absent.
