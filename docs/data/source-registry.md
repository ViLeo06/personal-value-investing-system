# Data Source Registry — P0

This registry distinguishes **authority** from **convenience**. Free access does not automatically mean open-source licensing, and an open-source adapter does not make its upstream data PIT-correct.

| Code | Source | Role | Free | Open source | PIT | Priority | Policy |
|---|---|---|---:|---:|---|---:|---|
| CNINFO | 巨潮资讯网 | A-share disclosure evidence | yes | no | native | 10 | Primary evidence for A-share filings/announcement timestamps when applicable. |
| SSE | 上海证券交易所 | Shanghai exchange authority | yes | no | native | 10 | Security identity, announcements, calendar/events and official cross-checks. |
| SZSE | 深圳证券交易所 | Shenzhen exchange authority | yes | no | native | 10 | Security identity, announcements, listing/delisting events and calendar. |
| HKEXNEWS | HKEXnews | Hong Kong disclosure evidence | yes | no | native | 10 | Primary evidence for Hong Kong filings; preserve release timestamp. |
| HKEX | Hong Kong Exchanges and Clearing | Hong Kong exchange authority | yes | no | native | 15 | Listing/security metadata, calendar and corporate-action cross-checks. |
| AKSHARE | AKShare | Open-source adapter | yes | yes (MIT) | derived | 50 | Convenience/cross-check layer only; never authoritative for historical availability. |

## Admission rules

1. Official disclosure/exchange evidence outranks aggregators.
2. Every financial fact used in a historical decision needs an `available_at` timestamp and lineage to evidence or a documented derivation.
3. Revised values are appended as new versions; historical versions are not overwritten.
4. Adapter data must retain upstream source metadata where possible.
5. If free/open evidence cannot support a field, record a data-quality gap rather than silently filling it from a paid source.
6. Terms/licensing must be reviewed before redistributing raw source content. The repository should generally store metadata, hashes, parsers and reproducible retrieval instructions rather than bulk third-party data.

## Known hard gaps to solve before Gate 2

- survivorship-free historical A/H universe;
- complete delisting/ticker-change history;
- corporate actions sufficient for exact total-return reconstruction;
- historical index total-return benchmarks;
- publication-time-safe standardized financial facts at 30–100 company scale.
