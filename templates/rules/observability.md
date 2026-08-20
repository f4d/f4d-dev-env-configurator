---
id: observability
always_apply: false
---
# Observability

- Structured JSON logs. No `print`, no bare `console.log` outside local scripts.
- Every log line carries `request_id` (or `job_id`) and, where applicable, `tenant_id`.
- NEVER log: full request/response bodies, credentials, tokens, signatures, PII, or file contents.
- Log levels mean something: ERROR = a human must act; WARN = degraded but handled; INFO = state transitions; DEBUG = local only.
- Every external call logs duration and outcome, never the payload.
- `/healthz` (process alive) and `/readyz` (dependencies reachable) on every service.
