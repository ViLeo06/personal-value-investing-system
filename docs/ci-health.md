# Continuous-integration health

The authoritative branch-health signals are the actual workflow checks:

- Python test matrix: CPython 3.11, 3.12 and 3.13.
- Clean PostgreSQL bootstrap and double-seed idempotency.
- Database contract tests.

The separate CI outcome recorder only mirrors the upstream CI conclusion into a tracking issue. A green recorder job never substitutes for the matrix or database checks.
