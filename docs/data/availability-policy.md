# PIT availability policy

## Exact timestamps

When an official source supplies a trustworthy timestamp, `available_at` equals that timestamp. It is stored with a timezone and never replaced by the ingestion time.

## Date-only disclosures

A disclosure that has an official date but no trustworthy time is **not** assumed visible at midnight or before market open. It becomes eligible at the next open session's 09:30 local time, where the next session date is supplied by the versioned exchange calendar.

This is deliberately conservative. Source-specific evidence may later establish an exact earlier timestamp, which is stored as a new revision rather than overwriting the historical record.

## Daily market bars

A completed daily bar becomes usable after the official close plus a one-minute processing buffer:

- SSE/SZSE: 15:01 Asia/Shanghai;
- HKEX: 16:01 Asia/Hong_Kong.

A decision recorded exactly at the close therefore cannot use that same day's completed daily bar. A strategy that intentionally trades at or after close must declare a different execution convention and test it separately.

## Decision cutoffs

Every valuation/decision run stores a timezone-aware cutoff. Exchange-local conventions are resolved before querying PIT data. Cross-listed A/H securities keep separate market cutoffs, currencies and bar/action histories even when issuer fundamentals are shared.

## Calendar versioning

Weekends and holidays must not be inferred from a current calendar library. `master.trading_days` is versioned from an exchange/free authoritative source, and the run manifest identifies the calendar version used to determine next-session availability and execution dates.
