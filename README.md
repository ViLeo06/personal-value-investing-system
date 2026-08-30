# Value Investing Valuation System V1.2

A reproducible, point-in-time (PIT) value-investing research system for A/H shares.

## Goal

Turn the existing valuation-workbook methodology into a maintainable platform that can replay historical decisions using only information available at each decision time.

Core pipeline:

`Raw/Evidence -> PIT -> Fundamentals -> Driver Forecast -> Valuation -> Market Expectations -> Decision -> Walk-forward Backtest -> Attribution`

## Architecture decisions

- **Supabase/PostgreSQL** is the central source of truth for identities, PIT facts, model runs, audit lineage and backtest outputs.
- **Parquet + DuckDB** is the planned local analytical cache and batch-research layer, not the authoritative database.
- **Python** is the deterministic calculation engine.
- **Excel** remains a review, reconciliation and presentation layer—not the system of record.
- **Private research schemas** are not exposed through the Supabase Data API. A future application API must use a dedicated schema with explicit grants and RLS.
- **Free/open data policy**: missing data is surfaced as a data-quality gap rather than silently filled with paid or unverifiable values.

## Current status

The P0 engineering foundation and four-company **legacy architecture/golden-test bridge** are complete:

- canonical Supabase migrations are reproducible from GitHub;
- Moutai, Tencent, BYD and CMB issuer/security relationships are registered;
- deterministic PIT guards, DCF/reverse-solver primitives, Owner Earnings DCF and a corporate-action total-return ledger are implemented;
- four frozen 2021 valuation decisions, 2026 outcomes and explicit lineage/data-quality records are stored in Supabase;
- automated tests and GitHub CI verify reconciliation and leakage rules.

The legacy bridge is **not formal strategy evidence**. It was reconstructed from a 2026 workbook, uses a hand-picked sample, lacks some executable historical assumptions and contains proxy corporate-action dates/prices. Native archival PIT Gate 0 remains in progress.

## Repository layout

- `docs/PLAN.md` — execution plan and completion boundaries
- `docs/architecture/` — architecture decision records
- `docs/data/` — data contracts, source policy and documented gaps
- `docs/research/` — valuation and backtest research rules/reports
- `src/value_investing/` — deterministic Python research engine
- `supabase/migrations/` — authoritative database schema history
- `supabase/seeds/` — idempotent reference and Gate-0 bridge data
- `tests/` — formula, PIT, reconciliation and database assertions
- `artifacts/` — deterministic generated research manifests

## Run tests

```bash
python -m pip install -e ".[dev]"
pytest -q
```

## Non-negotiable PIT rule

For a historical decision timestamp `T`, a record is eligible only when `available_at <= T`. Current or revised values not available at `T` must never enter the historical run.
