# Security note

Supabase's generic table inventory currently reports RLS disabled on the internal research tables. This project intentionally keeps `master`, `raw`, `pit`, `fundamentals`, `model`, `backtest`, and `audit` as private schemas and revokes schema usage and table privileges from `anon` and `authenticated`.

Verified on 2026-08-30:
- `has_schema_privilege(..., 'USAGE') = false` for both client roles on all seven schemas.
- no direct table grants exist for either client role on those schemas.
- Supabase security advisor returned no security lints.

RLS should still be enabled as defense in depth before any of these schemas/tables are exposed to client roles. If a frontend API is introduced, prefer a dedicated `api` schema with explicit grants, RLS policies and security-invoker views rather than exposing internal research schemas.
