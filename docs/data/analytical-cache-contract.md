# Analytical cache contract — Parquet + DuckDB

## Purpose

Supabase/PostgreSQL remains the authoritative source of truth. Parquet files are immutable analytical exports used for local scans, vectorized diagnostics and walk-forward batches. DuckDB is a query engine over those exports, not an independent truth store.

## Export identity

Every export is identified by:

- `dataset_name`
- `schema_version`
- `source_snapshot_hash`
- `exported_at`
- `row_count`
- `content_hash`
- ordered primary/business-key columns
- minimum and maximum `available_at` where applicable

An export is valid only when its manifest hash and every file hash match. Files are never overwritten in place; a correction creates a new snapshot directory.

## Directory layout

```text
lake/
  manifests/
    <source_snapshot_hash>.json
  master/
    issuers/schema=v1/part-*.parquet
    securities/schema=v1/exchange=<MIC>/part-*.parquet
    universe_memberships/schema=v1/universe=<code>/year=<YYYY>/part-*.parquet
  pit/
    financial_facts/schema=v1/issuer=<issuer_code>/period_year=<YYYY>/part-*.parquet
    market_bars/schema=v1/exchange=<MIC>/trade_year=<YYYY>/part-*.parquet
    corporate_actions/schema=v1/exchange=<MIC>/effective_year=<YYYY>/part-*.parquet
    fx_rates/schema=v1/pair=<BASE_QUOTE>/rate_year=<YYYY>/part-*.parquet
    macro/schema=v1/series=<series_code>/observation_year=<YYYY>/part-*.parquet
  fundamentals/
    normalized_facts/schema=v1/issuer=<issuer_code>/period_year=<YYYY>/part-*.parquet
  model/
    valuation_runs/schema=v1/model_family=<family>/decision_year=<YYYY>/part-*.parquet
    assumptions/schema=v1/model_family=<family>/decision_year=<YYYY>/part-*.parquet
    outputs/schema=v1/model_family=<family>/decision_year=<YYYY>/part-*.parquet
  backtest/
    decisions/schema=v1/run=<run_hash>/part-*.parquet
    transactions/schema=v1/run=<run_hash>/trade_year=<YYYY>/part-*.parquet
    positions/schema=v1/run=<run_hash>/trade_year=<YYYY>/part-*.parquet
    daily_performance/schema=v1/run=<run_hash>/trade_year=<YYYY>/part-*.parquet
    outcomes/schema=v1/run=<run_hash>/part-*.parquet
    attribution/schema=v1/run=<run_hash>/part-*.parquet
```

Issuer and security codes are sanitized identifiers, never display names. A/H securities remain separate partitions even when they share one issuer.

## PIT columns that must survive export

No export may drop the fields needed to reconstruct historical visibility:

- `period_start`
- `period_end`
- `published_at`
- `available_at`
- `ingested_at`
- `revision_no`
- `source_document_id` or stable document fingerprint
- `record_hash`
- `source_id`
- `batch_id`

For a decision timestamp `T`, every DuckDB query must retain the predicate:

```sql
available_at <= T
```

When multiple revisions of one business fact are eligible, the query selects the latest eligible `available_at`, then highest eligible `revision_no`; it never selects the present-day final row first and filters later.

## Export boundaries

Exports are generated from a frozen `audit.data_snapshots` manifest or a recorded ingestion batch. Ad-hoc `SELECT *` exports without a snapshot hash are prohibited for formal research.

Large binary evidence files do not belong in Parquet. The export keeps hashes, stable URLs/storage URIs, publication metadata and parser versions; binaries remain in evidence storage.

## DuckDB usage rules

- read Parquet directly; do not import another mutable database copy;
- materialize only explicitly versioned intermediate tables;
- store SQL text and DuckDB version in the run manifest;
- write results back to Supabase only after deterministic validation;
- never let a DuckDB temporary table become an undocumented source of model assumptions;
- use exact decimal types for money and shares when values will be reconciled to PostgreSQL;
- convert to floating point only inside numerical valuation routines with tolerance-tested outputs.

## Scaling expectation

For 30–100 companies, annual/interim facts and daily A/H bars remain comfortably within a single-machine columnar workflow. Distribution by Spark/Kafka is deferred until measured scans, not intuition, show DuckDB/Parquet is insufficient.

## Validation

A cache export passes only when:

1. row counts match the source query;
2. ordered key hashes match;
3. no record lacks its required PIT fields;
4. no duplicate business key exists inside one source revision;
5. the manifest references the exact source snapshot and code commit;
6. a sample historical decision reproduces the PostgreSQL result within declared numeric tolerance.
