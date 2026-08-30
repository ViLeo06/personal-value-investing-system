# Supabase database

The SQL files in `migrations/` are the authoritative schema history for the central research database.

Research schemas are intentionally private and should not be added to Supabase Data API exposed schemas. If an application API is needed later, create a dedicated `api` schema with explicit grants and RLS/security-invoker views.
