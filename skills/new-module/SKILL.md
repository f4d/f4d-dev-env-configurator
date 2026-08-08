---
name: new-module
description: Scaffold a complete vertical slice — migration, model, repository, service, API route, tests, and fixtures — matching the conventions already in this repo. Use when the user says "add a module", "new resource", "new entity", "build the X feature", or asks for a new CRUD surface. Ensures feature #10 looks exactly like feature #1.
---

# New Module

One entity, all layers, in one pass. Read `.claude/rules/` first — this skill produces code in *this repo's* style, not a generic style.

## Ask only what you cannot infer

1. Entity name (singular)
2. Fields: name, type, nullable, indexed
3. Ownership/tenancy — who can see it
4. Which operations are needed (default: list, get, create, update; ask before adding delete)

## Produce, in order

| Layer | File | Notes |
|---|---|---|
| Migration | `migrations/` | FK indexes included. Reversible. |
| Model/schema | per repo convention | Generated types regenerated after |
| Repository | query layer | No raw SQL above this layer |
| Service | business logic | Where invariants are enforced |
| Route | `/api/v1/<plural>` | Validated at boundary, paginated list, standard error envelope |
| Tests | unit + integration | Integration hits the local stack |
| Fixtures | seed additions | Include a null-heavy and a unicode row |

## Rules

- Never invent a field the user did not ask for. No speculative `metadata` JSON columns.
- Authorization is written now, not "added later." A route without an ownership check is not done.
- List endpoints paginate from the first commit.
- Run verify before reporting completion. Report the failing check, not a summary, if it fails.
