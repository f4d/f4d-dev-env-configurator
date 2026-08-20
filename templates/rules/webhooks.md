---
id: webhooks
always_apply: false
---
# Webhooks

## Receiving
- Verify the signature BEFORE parsing the body. Compare with constant-time equality (`hmac.compare_digest` / `crypto.timingSafeEqual`). Never `==`.
- Sign `{timestamp}.{raw_body}`. Reject timestamps older than 5 minutes.
- Return 200 within 500ms. All real work goes on a queue. No exceptions.
- Every event carries `event_id` (UUIDv7) and `occurred_at`. Dedupe on `event_id` against a persisted seen-set. Handlers are idempotent.
- Never log a full payload or any signature header.

## Sending
- Retry: 1s, 4s, 15s, 60s, 300s with jitter, then dead-letter. Never retry forever.
- Include `event_id`, `occurred_at`, `event_type`, and a schema `version` in every payload.
- A new event type requires a schema in the contract repo first. Never invent a field at the call site.
