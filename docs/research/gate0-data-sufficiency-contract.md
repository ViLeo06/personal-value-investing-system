# Gate 0 data-sufficiency contract

A valuation run must not silently substitute missing inputs.

For the Moutai 2021-04-01 prototype, the six already-ingested annual-report facts are valid PIT evidence, but they are insufficient for a completed Owner Earnings DCF. The run remains `blocked_data` until the following are source-backed and time-eligible:

- depreciation and amortization;
- non-cash adjustments;
- maintenance capital expenditure, separated from growth capex;
- incremental working-capital investment;
- point-in-time shares outstanding;
- net cash under the selected valuation convention;
- unadjusted decision-date market price;
- dividends, splits and other corporate actions required for total return.

The Python Gate-0 module raises `DataSufficiencyError` when these inputs are absent. Reverse DCF calls the same forward valuation function; it is not a separate formula stack.

## Status semantics

- `queued`: run registered but not started;
- `running`: deterministic calculation in progress;
- `blocked_data`: one or more required, source-backed PIT inputs are unavailable;
- `failed`: inputs were sufficient but calculation or validation failed;
- `completed`: outputs, hashes and lineage were successfully persisted.

A `blocked_data` run is a successful control outcome, not a failed valuation. It prevents false precision and future-data leakage.
