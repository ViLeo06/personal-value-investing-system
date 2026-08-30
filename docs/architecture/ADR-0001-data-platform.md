# ADR-0001: Central database and analytical cache

- Status: Accepted
- Date: 2026-08-30

## Decision

Use Supabase/PostgreSQL as the central source of truth. Use Parquet + DuckDB as a disposable/rebuildable analytical cache for local batch research and walk-forward computation.

## Rationale

The system needs durable identities, bitemporal facts, revision history, lineage, model versions, and reproducible run manifests. PostgreSQL is a better authority for these relationships than a collection of local files. DuckDB/Parquet remains valuable for fast scans and batch analytics but must be rebuildable from authoritative data.

## Consequences

- Database migrations are versioned in Git.
- Local Parquet/DuckDB files are never the only copy of authoritative research facts.
- Secrets and raw datasets are not committed to GitHub.
- Future APIs should expose dedicated views/contracts rather than raw research tables.
