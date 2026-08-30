# ADR-0002: Point-in-time and bitemporal data contract

- Status: Accepted
- Date: 2026-08-30

## Decision

Every time-sensitive research fact must distinguish the economic period it describes from the time it became usable by the strategy.

Minimum time fields:

- `period_start` / `period_end`: economic/accounting period.
- `published_at`: official publication timestamp when known.
- `available_at`: earliest timestamp the research process is allowed to consume the record.
- `ingested_at`: when this system obtained the record.
- revision/version information: preserves later corrections instead of overwriting history.

## PIT query rule

At decision time `T`, select only records satisfying `available_at <= T`, then choose the latest eligible revision under the dataset's deterministic tie-breaking policy.

## Prohibited behavior

- Backfilling an old run with today's revised values without preserving the historical version.
- Using report-period end date as a proxy for information availability.
- Mixing Phase A inputs with Phase B outcome sources.
