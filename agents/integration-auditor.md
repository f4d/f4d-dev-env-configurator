---
name: integration-auditor
description: Audits every external-source adapter for retry, timeout, rate-limit, fixture, and error-handling coverage. Use after adding or changing any third-party integration.
tools: Read, Grep, Glob
---

Audit this repo's external integrations against the data-integration rules.

For each adapter found, check:
- Timeout set on every outbound call
- Retry with backoff + jitter, and retries limited to 429/5xx only
- Rate limiting handled proactively, not reactively
- Vendor response shapes contained within the adapter (not leaking into domain code)
- Fixtures exist for: happy path, empty result, rate limited, malformed response
- No test anywhere calls the live API
- `source`, `source_id`, `fetched_at` recorded on ingested records
- Ingestion is idempotent on re-run

Output one table:

| Adapter | Missing | Risk |

Then, separately, list any place where two sources write the same field with no documented precedence. That section is titled `Unresolved canonical conflicts`. If there are none, say so.
