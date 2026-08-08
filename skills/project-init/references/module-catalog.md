# Rules Module Catalog

Each module is a single file copied into `.claude/rules/`. Include only what the interview justified. Every unnecessary module is context Claude burns on every relevant turn.

| Module | Always? | Trigger | Adds |
|---|---|---|---|
| `core` | YES | — | Git discipline, commit format, verify-before-commit, no-secrets |
| `api` | YES if any HTTP surface | Q3/Q5 | Error envelope, validation at the boundary, status codes, versioning, pagination |
| `database` | YES if DB | Q4 | Migration policy, naming, indexes, no raw SQL in handlers, N+1 |
| `python` | if Python | Q2 | uv, ruff, strict mypy, no bare except, Decimal over float |
| `typescript` | if TS/JS | Q2 | strict tsconfig, no `any`, no default exports, zod at boundaries |
| `data-integration` | if multi-source | Q5/R3 | Adapter interface, recorded fixtures, never test against live vendors, retry/backoff, rate limits, canonical-record reconciliation |
| `webhooks` | if inbound callbacks | Q6 | HMAC before parse, constant-time compare, 200-fast + async, event_id dedupe, replay window |
| `contracts` | if multi-repo | Q7 | Spec-first, generated types only, version pinning, drift gate |
| `storage` | ask | R3 | Bucket layout, key naming, presigned URLs, content-type, size limits, lifecycle, no PII in keys |
| `determinism` | ask | R3 | JCS canonicalization, golden fixtures, forbidden fields in hashed payloads, versioned hash paths |
| `money` | ask | R3 | Decimal only, splits sum exactly, idempotency keys, property tests, never trust client price |
| `blockchain` | ask | R3 | Foundry, gas snapshots, CEI ordering, fork testing, no broadcast from agent |
| `keysafety` | auto with blockchain | R3 | Hard blocks on keys, mnemonics, mainnet RPC |
| `frontend` | ask | R3 | Perf budgets, a11y, no client-side waterfalls |
| `livesystem` | ask | Q8 | Prod is read-only to agents, migration notes required, no schema change without plan |
| `dataprotection` | ask | R3 | PII inventory, no PII in logs/keys/URLs, retention, redaction in fixtures |
| `guards` | **always** | — | Red-then-green, guard hygiene, where a rule belongs |
| `silent-degradation` | **always** | — | No degrade-to-default, catch→[] trap, guess lists, hardcode boundary, raw ids |
| `capability-parity` | if UI + API must agree | Q3+Q5 | Consumer enumeration, UI-as-proof, row-vs-call failure, preview/execute parity |
| `statelessness` | if >1 instance, ever | Q5 | No module-level state, no in-process locks/schedulers/limiters, nothing on local disk, migrations not at boot, two-instance local stack, cross-instance tests |
| `observability` | recommend if any of the above | — | Structured logs, correlation IDs, no payload logging, health endpoints |

## Sizing guidance

- **Typical API + DB + integrations project:** core, guards, silent-degradation, api, database, python *or* typescript, data-integration, observability. Eight files, ~300 lines total.
- **`guards` and `silent-degradation` are not optional.** They are the two modules that address the failure class which survives review — output that looks plausible while being wrong. Every project gets them.
- **Add storage only when asked for.** Most projects touch files; few need a storage *policy*. The policy is worth it when files are user-supplied, large, or served publicly.
- **`determinism` without `storage` is almost never right.** `storage` without `determinism` is common and fine.
- **`statelessness` is decided by deployment, not by preference.** If the project will ever run two instances, it is required — and the local stack changes with it. Retrofitting statelessness after the first production incident is far more expensive than starting with a two-instance compose file.
- If a project needs more than ten modules, it is probably two projects.
