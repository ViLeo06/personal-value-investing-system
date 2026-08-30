# Immutable evidence storage

## Policy

Every filing, announcement, market-data response or corporate-action document must be hashed before parsing. A parser output without retained source bytes (or a stable official HTML capture) cannot support a fully validated run.

## Retrieval boundary

`value_investing.evidence.fetch_evidence`:

- accepts HTTPS only;
- accepts only configured official/free source domains;
- re-validates the final redirect host;
- enforces a hard byte limit;
- computes SHA-256 from exact bytes;
- optionally verifies an expected SHA-256;
- performs no financial parsing.

Source-specific adapters may discover URLs and publication metadata, but they must pass exact bytes through this boundary before parsing.

## Content-addressed layout

The local/cache representation is:

```text
<root>/sha256/<first-two-hex>/<full-sha256>
```

Objects are written through a temporary file and atomic rename. Existing objects are re-hashed and never overwritten.

The durable Supabase bucket is private and named `research-evidence`. The intended object key is likewise content addressed, for example:

```text
sha256/ab/abcdef...<64 hex characters>
```

`raw.documents.storage_uri` records the durable URI and `raw.documents.content_hash` records the SHA-256. Database rows do not contain raw binary content.

## Upload security

A future upload adapter must:

1. run server-side with a secret/service credential;
2. never expose that credential in GitHub, logs or a browser client;
3. upload to the private bucket;
4. re-download or otherwise verify the stored object hash;
5. insert/update the `raw.documents` row only after storage verification;
6. be idempotent by content hash;
7. reject arbitrary hosts and oversized files.

The existing connected Supabase management interface can provision the private bucket and database metadata but does not expose a safe object-upload operation. Until a server-side uploader is connected, local content-addressed evidence is considered retained for development but not durable enough for a `validated` research release.
