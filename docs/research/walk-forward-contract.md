# Walk-forward Contract V1.2

For each historical decision timestamp:

1. Resolve the historically eligible universe.
2. Freeze a data snapshot cutoff.
3. Query only facts with `available_at <= decision_at`.
4. Normalize fundamentals using versioned rules.
5. Run the assigned valuation family and scenario set.
6. Run reverse valuation/market-expectations diagnostics.
7. Freeze the decision before observing future returns.
8. Apply trades using explicit execution timing and transaction-cost rules.
9. Apply corporate actions from an event ledger.
10. Attribute subsequent return against benchmark and valuation drivers.

A run is reproducible only if the code commit, model version, data snapshot, configuration, universe membership, calendar/corporate-action versions, and output hash are recorded.
