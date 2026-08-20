---
id: data-integration
always_apply: false
---
# Data Integration

The core discipline of this project: many sources, one truth.

## Adapters
- Every external source sits behind an interface defined by US, not by the vendor. Vendor response shapes never leak past the adapter.
- One adapter file per source. It owns: auth, retries, rate limiting, pagination, and mapping to our internal model.
- Adapters return our types. If a vendor field is unmapped, it is dropped explicitly, not passed through.

## Testing
- NEVER write a test that calls a live third-party API. Record real responses once, redact them, commit as fixtures.
- Every adapter has at least: a happy-path fixture, an empty-result fixture, a rate-limited fixture, and a malformed-response fixture.
- When a vendor changes, the fixture is updated in a dedicated commit that touches nothing else.

## Reliability
- Retry with exponential backoff plus jitter. Retry only 429 and 5xx. Never retry a 4xx.
- Every outbound call has a timeout. No unbounded waits.
- Respect documented rate limits proactively; do not discover them via 429s.
- Metered/paid APIs: log call counts, and never call one from a test or a dev-loop script.

## Reconciliation
- There is exactly one canonical record per entity. Document which source wins per field, in `.claude/rules/canonical.md` or the README.
- Every ingested record stores its `source`, `source_id`, and `fetched_at`.
- Conflicts are surfaced, not silently resolved. A field where two sources disagree is logged and, where it matters, flagged for review.
- Ingestion is idempotent. Re-running yesterday's sync changes nothing.
