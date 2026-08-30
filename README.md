# Value Investing Valuation System V1.2

A reproducible, point-in-time (PIT) value-investing research system for A/H shares.

## Goal

Turn the existing valuation workbook methodology into a maintainable research platform that can replay historical decisions using only information that was available at each historical decision time.

Core pipeline:

`Raw/Evidence -> PIT -> Fundamentals -> Driver Forecast -> Valuation -> Market Expectations -> Decision -> Walk-forward Backtest -> Attribution`

## Architecture decisions

- **Supabase/PostgreSQL**: central source of truth for metadata, PIT facts, model runs, audit lineage, and backtest outputs.
- **Parquet + DuckDB**: local analytical cache and batch-research layer. They are not the authoritative database.
- **Python**: deterministic calculation engine.
- **Excel**: review, reconciliation, and presentation layer; not the system of record.
- **Private database schemas**: research tables are not directly exposed through Supabase Data API. A dedicated API schema may be introduced later.
- **Data policy**: free/open sources only. Missing data is surfaced as a data-quality gap rather than silently replaced by paid/proprietary data.

## Status

V1.2 foundation phase. Database contracts are being established before valuation logic is ported.

## Repository layout

- `docs/architecture/` architecture decision records (ADRs)
- `docs/data/` data contracts, dictionary, source policy
- `docs/research/` valuation and backtest research rules
- `supabase/migrations/` authoritative database migrations
- `src/value_investing/` future deterministic Python engine
- `tests/` reconciliation and PIT safety tests
- `config/` non-secret project configuration examples

## Non-negotiable PIT rule

For a historical decision timestamp `T`, a record is eligible only when its `available_at <= T`. Current/revised values that were not available at `T` must never leak into a historical run.
