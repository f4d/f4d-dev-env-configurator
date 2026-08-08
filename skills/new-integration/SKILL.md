---
name: new-integration
description: Add a new external data source as a properly isolated adapter with fixtures, retries, timeouts, rate limiting, and reconciliation mapping. Use whenever the user says "integrate with X", "pull data from Y", "connect to the Z API", or adds any third-party source. Prevents vendor shapes from leaking into the domain.
---

# New Integration

## Ask

1. Which system, and what does it give us?
2. Auth method, and is it metered or paid?
3. Read, write, or both?
4. Which of our canonical fields does it populate — and if another source also populates them, **which wins?**
5. Rate limits and pagination style?

Question 4 is the one that matters. If the user has not decided precedence, stop and design that before writing code.

## Produce

1. **Adapter interface** — our types, our names. Vendor vocabulary stops here.
2. **Client** — timeout on every call, backoff+jitter retry on 429/5xx only, proactive rate limiting, pagination handled internally.
3. **Mapper** — vendor response → our model. Unmapped fields dropped explicitly with a comment.
4. **Fixtures** — happy path, empty, rate-limited, malformed. Recorded from real responses, redacted in the same commit.
5. **Tests** — against fixtures only. Assert that a re-run is idempotent.
6. **Precedence entry** — append this source to the canonical-record table in CLAUDE.md or `.claude/rules/canonical.md`.
7. **Env vars** — added to `.env.example` with empty values.

## Never

- Call the live API from a test, a seed, or a dev script.
- Store a vendor response verbatim as the canonical record.
- Silently overwrite a field another source owns.
