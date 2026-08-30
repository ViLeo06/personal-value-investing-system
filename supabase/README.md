# Supabase database

The SQL files in `migrations/` are the authoritative schema history for the central research database and must be applied in lexical order.

## Foundation compatibility note

The originally retained `202608300001_foundation.sql` ends midway through `model.run_assumptions`; it is preserved as historical evidence rather than silently rewritten. `202608300001_zz_foundation_tail.sql` completes the missing model, backtest and audit tables before migration 002 adds revision/index integrity.

A fresh PostgreSQL/Supabase bootstrap is therefore:

```text
202608300001_foundation.sql
202608300001_zz_foundation_tail.sql
202608300002_indexes_and_revision_integrity.sql
202608300003_decision_outcomes_and_attribution.sql
```

GitHub Actions verifies this exact sequence against PostgreSQL 17 and then applies every seed twice.

Research schemas are intentionally private and should not be added to Supabase Data API exposed schemas. If an application API is needed later, create a dedicated `api` schema with explicit grants and RLS/security-invoker views.
