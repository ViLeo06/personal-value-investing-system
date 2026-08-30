# Data Source Policy V1.2

## Principle

The project uses free/open-access sources only unless this policy is explicitly revised by the owner.

## Source preference order

1. Official exchange/regulator/issuer disclosures.
2. Official public datasets/APIs.
3. Open-source adapters that retrieve the same public source and preserve provenance.
4. Public websites used only when licensing/terms and reproducibility are acceptable.

## Required provenance

Every imported dataset must record, where applicable:

- source/provider name
- source URL or document identity
- retrieval timestamp
- publication timestamp
- availability timestamp
- parser/adapter version
- content or record hash
- license/terms notes

## Data gap rule

If a reliable free source cannot satisfy a required field, create a data-quality issue and leave the field unavailable. Do not silently substitute a paid feed, present-day value, or hand-waved estimate in a historical PIT run.
