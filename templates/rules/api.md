---
id: api
always_apply: false
---
# API

- Versioned from day one: all routes under `/api/v1/`.
- Validate at the boundary, once. Python: Pydantic v2. TS: zod. Handlers receive parsed, typed input and may assume it is valid.
- One error envelope, everywhere:
  `{ "error": { "code": "SNAKE_CASE_CODE", "message": "human readable", "details": {...}, "request_id": "..." } }`
- Status codes: 400 malformed, 401 unauthenticated, 403 authenticated but not allowed, 404 not found or not visible to caller, 409 conflict, 422 semantically invalid, 429 rate limited, 5xx our fault only.
- Never leak internal IDs, stack traces, ORM errors, or vendor error text to a client.
- List endpoints are paginated from the first commit. Cursor-based, never offset, for anything that can grow.
- Every mutating endpoint accepts an `Idempotency-Key` header where a retry is plausible.
- Every request gets a `request_id`, logged and returned in the error envelope.
