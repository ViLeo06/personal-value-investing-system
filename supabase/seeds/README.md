# Supabase seeds

Seeds in this directory are ordered engineering/data operations. They must be reviewed in sequence and are expected to be idempotent unless a file explicitly states otherwise.

## Execution rules

1. Migrations define schema and database functions; seeds load reference data or invoke fixed capture/reconciliation workflows.
2. Never edit or delete raw evidence to make a seed pass.
3. A failed capture creates or preserves a data-quality issue. It must not backfill a guessed value.
4. Formal valuation inputs require qualifying evidence and immutable hashes.
5. Engineering proxy runs are never promoted into formal investment conclusions.

## Superseded draft

`025_build_moutai_accounting_input_candidates.sql` is an **unexecuted audit draft**. It exposed a PostgreSQL portability issue (`count(distinct ...) over (...)`) during static review and must not be run.

The supported accounting-candidate workflow is:

- migration `202608300017_accounting_candidate_functions.sql`;
- migration `202608300018_accounting_page_match_single_call.sql`;
- seed `026_refresh_moutai_accounting_candidates.sql`.

The draft remains in version history so the review trail is not rewritten.

## Current Moutai evidence sequence

- `021_capture_moutai_official_pdf.sql`
- `022_parse_moutai_official_report.sql`
- `023_parse_moutai_official_report_v2.sql`
- `024_validate_moutai_known_facts_against_official_pdf.sql`
- `026_refresh_moutai_accounting_candidates.sql`
- `027_capture_moutai_sse_market_v2.sql`
- `028_capture_and_reconcile_moutai_dividends.sql`

Each step is fail-closed: missing files, ambiguous accounting fields, inconsistent prices or unmatched corporate actions remain visible as open quality issues and failed Gate 0 checks.
