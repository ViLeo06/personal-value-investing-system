# Execution Plan — V1.2

Status legend: DONE / IN PROGRESS / BLOCKED / NEXT.

## Track A — trustworthy platform foundation

1. DONE — Supabase/PostgreSQL is the central source of truth; DuckDB/Parquet is reserved for analytical cache and batch work.
2. DONE — PIT/bitemporal contract: historical runs may consume only records with `available_at <= decision_at`.
3. DONE — Canonical foundation and revision-preserving migrations are stored in GitHub and applied to Supabase.
4. DONE — Internal schemas are not granted to `anon` or `authenticated`; a future application API must use a dedicated RLS-protected schema.
5. DONE — Gate-0 issuer/security identity map covers Moutai, Tencent, BYD and CMB, including A/H relationships where applicable.
6. DONE — Initial free-source registry covers official A/H disclosure/exchange sources and AKShare as a non-authoritative adapter.
7. DONE — Deterministic hashing, PIT guards, DCF primitives, bounded reverse solver, Owner Earnings DCF, FCFF, residual income and corporate-action total-return accounting have automated tests.
8. DONE — GitHub CI passes the full 140-test suite on Python 3.11, 3.12 and 3.13.
9. DONE — Clean PostgreSQL bootstrap, double-seed idempotency and database contract workflows pass independently of the live Supabase project.
10. DONE — Segment master data, PIT segment facts, share-class facts and their `as_of` version functions are present in GitHub and live Supabase.
11. DONE — Supabase security advisor reports no security lints; foreign-key index findings are resolved. Remaining performance notices are unused-index informational messages expected at Gate-0 volume.

## Track B — legacy architecture/golden-test bridge

1. DONE — The 2021–2026 workbook is registered as a user-owned legacy evidence artifact with a SHA-256 hash.
2. DONE — Four frozen valuation runs, scenario outputs, decisions, endpoint market prices, 28 corporate actions and lineage records are loaded into Supabase.
3. DONE — Database leakage checks return zero Phase-B prices and zero subsequent corporate actions at the Phase-A cutoff.
4. DONE — Corporate-action arithmetic reproduces the workbook's ending shares and endpoint TSR/CAGR for all four companies.
5. DONE — Known limitations are stored as data-quality issues.

**Boundary:** this bridge validates architecture and reconciliation only. It is not formal evidence of investment skill because the workbook was created in 2026, the sample is hand-picked and some historical assumptions/actions are proxies.

## Track C — native PIT Gate 0

1. IN PROGRESS — Complete Moutai's first native official-evidence snapshot, including authoritative market data, archived filing bytes and corporate actions.
2. IN PROGRESS — CMB's native residual-income replay and deterministic tests exist; complete first-party evidence archiving and market/corporate-action reconciliation.
3. NEXT — Implement native Tencent platform FCFF/SOTP and BYD value-driver FCFF runs from contemporaneous evidence.
4. NEXT — Expand the standardized metric dictionary and normalization rules for all four model families.
5. NEXT — Create three historical decision snapshots per company from contemporaneous official/free evidence.
6. NEXT — Reconcile each run against V1.1/legacy outputs where comparable and preserve documented differences.
7. NEXT — Freeze Phase A, reveal Phase B only after maturity, and generate reproducible attribution.

## Later gates

- Gate 1: 12–20 mixed-quality companies to stress normalization and model routing.
- Gate 2: 30-company formal walk-forward with historical universe membership and simple baselines.
- Gate 3: 60–100 companies after model-family coverage, total-return accounting and attribution are stable.

## Engineering rule

Do not optimize for feature count. Optimize for auditability, deterministic replay, explicit data gaps and resistance to look-ahead and survivorship bias.
