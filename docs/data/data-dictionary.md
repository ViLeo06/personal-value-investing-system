# Data Dictionary V1.2 (Foundation)

## Schemas

| Schema | Purpose |
|---|---|
| `master` | Issuers, securities, identifiers, trading calendars |
| `raw` | Sources, ingestion batches, original documents/evidence |
| `pit` | Point-in-time financial facts, prices, corporate actions, FX, macro observations |
| `fundamentals` | Standardized/normalized accounting metrics and documented adjustments |
| `model` | Model versions, issuer-to-model routing, valuation runs, assumptions and outputs |
| `backtest` | Historical universes, walk-forward decisions, trades, positions and performance |
| `audit` | Data snapshots, lineage and data-quality issues |

## Canonical identity

An `issuer` is the economic company/legal reporting entity. A `security` is a tradable listing/share class. One issuer may map to multiple securities (for example A and H shares).

## Availability semantics

`available_at` is the hard anti-look-ahead field. Historical logic must never infer availability from `period_end`.
