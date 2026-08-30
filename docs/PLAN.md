# Execution Plan — V1.2

Status legend: DONE / IN PROGRESS / BLOCKED / NEXT.

## P0 trustworthy replay foundation

1. DONE — Central platform: Supabase/PostgreSQL as source of truth; DuckDB/Parquet as analytical cache.
2. DONE — PIT/bitemporal contract: historical runs may only consume records with `available_at <= decision_at`.
3. DONE — Core schemas and revision-preserving indexes applied to Supabase.
4. DONE — Private-schema access boundary verified for `anon` and `authenticated` roles.
5. DONE — Gate-0 issuer/security identity map seeded for Moutai, Tencent, BYD and CMB, including A/H share relationships where applicable.
6. DONE — Initial source registry seeded with official A/H disclosure/exchange sources and AKShare as a non-authoritative open-source adapter.
7. IN PROGRESS — Evidence ingestion and first historical PIT snapshot.
8. NEXT — Metric dictionary + normalization rules for the four model families.
9. NEXT — Deterministic valuation engine and Reverse DCF solver.
10. NEXT — Corporate-action-aware total return ledger.
11. NEXT — Golden tests against V1.1 and PIT leakage tests.
12. NEXT — Gate 0: four companies × three historical decision snapshots.

## Completion gates

- Gate 0 passes only when a frozen historical decision can be reproduced from evidence and hashes without using future data.
- Gate 1 expands to 12–20 mixed-quality companies only after Gate 0 passes.
- Gate 2 expands to 30 companies and formal walk-forward comparisons only after total-return and historical-universe handling pass reconciliation.
- Gate 3 expands to 60–100 companies after model-family coverage and attribution are stable.

## Engineering rule

Do not optimize for feature count. Optimize for auditability, deterministic replay, explicit data gaps and resistance to look-ahead/survivorship bias.
