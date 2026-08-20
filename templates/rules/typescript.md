---
id: typescript
always_apply: false
---
# TypeScript

- `pnpm` only, version pinned via `packageManager` + corepack. Never `npm` or `yarn` in this repo.
- `tsconfig`: `strict: true`, `noUncheckedIndexedAccess: true`, `exactOptionalPropertyTypes: true`.
- `any` is banned. `unknown` plus a zod parse at the boundary instead.
- Named exports only. No default exports.
- Validate all external input with zod — request bodies, env vars, third-party responses. Infer types from the schema, never declare them twice.
- No floating promises. Every async call is awaited or explicitly handled.
- Errors: throw typed error classes, never bare strings.
- Tests: `vitest`. Integration tests run against the local docker stack, not mocks, wherever practical.
