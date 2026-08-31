# V1.2 implementation status

Last structural update: 2026-08-30.

This document describes implemented capabilities and known workstreams. It is **not** the authoritative pass/fail record. The source of truth is:

```sql
select * from audit.gate0_status();
select * from audit.gate0_overall();
```

Every capture is append-only in `audit.gate_status_history`.

## Implemented foundation

- Supabase/PostgreSQL central research database.
- Private schemas for master, raw evidence, PIT facts, normalized fundamentals, models, backtests and audit records.
- Issuer/security separation for A/H share classes.
- Content-based PIT snapshot hashes independent of surrogate database IDs.
- Service-role-only PIT query functions and snapshot builders.
- Versioned raw records and provider-field mappings.
- Evidence grades, fixed evidence requirements and fail-closed Gate 0 checks.
- Deterministic model router and four initial valuation families.
- Shared forward/reverse valuation primitives.
- Explicit decision-reference versus later execution-price timing.
- Corporate-action event model and total-return ledger.
- Daily backtest ledger, metrics, attribution and independent integrity checks.
- Immutable run manifests and historical gate-status captures.
- Excel Golden Test extraction/comparison tooling.
- Free/open-source evidence capture workflows with raw-response hashes.

## Gate 0 scope

Gate 0 is complete only when all of the following are true:

1. Four validation companies have three mature historical snapshots each.
2. Every historical snapshot uses only records available at the decision cutoff.
3. All formal model inputs have qualifying evidence.
4. Decision prices and execution prices are independently validated.
5. Corporate actions reconcile to official implementation announcements.
6. Total return, daily NAV, drawdown and attribution reconcile.
7. V1.1 Excel baselines are mapped and all twelve Golden Tests pass.
8. Each run has an immutable manifest, input hash and output/result hash.

## Moutai first-chain status model

The first formal run is designed to remain `blocked_data` until the accounting bridge and evidence gate pass. Engineering proxy runs are stored separately with `proxy` labels and can never be promoted into an investment conclusion.

The frozen Moutai accounting policy is in:

- `docs/research/moutai-owner-earnings-policy.md`

The first-chain workstreams are:

- official 2020 annual-report PDF capture, hashing and page-level evidence;
- audited D&A and itemized non-cash adjustments;
- maintenance-capex classification;
- operating working-capital bridge;
- point-in-time common shares and net cash;
- official reconciliation of decision/execution prices;
- official reconciliation of all five-year cash dividends;
- V1.1 Excel Golden Test mapping.

## Reproducibility rules

- Never overwrite raw evidence.
- Never use current/revised facts in an earlier decision snapshot.
- Never infer publication availability from fiscal period end.
- Never treat a single derived provider as formal evidence.
- Never mix a proxy run with a formal run.
- Never mutate a frozen run manifest; append a superseding manifest.
- Never close a Gate item by deleting the requirement or quality issue.
