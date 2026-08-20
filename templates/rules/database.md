---
id: database
always_apply: false
---
# Database

- Schema is the source of truth. Generated types are never hand-edited.
- Every schema change is a migration file, checked in, reviewed, reversible. Never `db push` or auto-sync outside a local disposable DB.
- Naming: `snake_case` tables (plural) and columns. PKs `id`. FKs `<singular>_id`. Timestamps `created_at`, `updated_at` (timestamptz, UTC).
- Every FK has an index. Every column in a WHERE or ORDER BY on a growing table has an index.
- Money is `numeric`, never `float` or `double precision`.
- Soft delete via `deleted_at` only where the domain requires recovery — otherwise delete.
- No raw SQL inside route handlers. Queries live in a repository/query layer.
- Any query inside a loop is an N+1 until proven otherwise. Batch or join.
- Multi-step writes are transactional. Partial writes are a bug, not an edge case.
- After any schema edit: regenerate types, then run the verify command.
