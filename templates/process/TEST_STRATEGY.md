# Test Strategy

Applies the testing pyramid to the failure classes this framework actually has.
Coverage is not the target — catching the failure class that survives review is.

## The pyramid, mapped

```
        /  E2E  \          scaffold boots, verify passes, sync round-trips
       / Integration \     adapters vs fixtures, migrations vs real DB, hooks vs harness
      /    Unit Tests  \   pure logic, canonicalization, money math, mappers
```

Most projects here are API-based, DB-backed, multi-source. That shifts weight
**down and to the middle**: the expensive failures are in mappers, reconciliation,
and contract boundaries — not in UI flows.

## By component

| Component | Test type | Non-obvious thing to cover |
|---|---|---|
| API endpoints | Unit for logic, integration for HTTP, contract for consumers | Authorization on every route, not the happy path |
| Adapters | Integration against **recorded fixtures**, never live | Malformed and rate-limited responses, not just success |
| Reconciliation | Unit + property | Two sources disagreeing on the same field |
| Migrations | Integration against a real DB | Reversibility; behavior on a populated table |
| Money | Property | Conservation of value; splits summing exactly |
| Canonicalization / hashing | Golden fixture | Byte-exact output, versioned, never edited in place |
| Webhook receivers | Integration | Replayed event, bad signature, stale timestamp |
| Hooks | Harness (`tests/hooks_test.sh`) | The **fail-loud** path, not only block/allow |

## The seven guard tests

Ranked by how well each catches silent degradation — the class that survives
review because output still looks plausible. Each needs a failing-then-passing
proof before it counts.

| # | Test | Catches |
|---|---|---|
| 1 | Collection non-empty before any assertion over it | Vacuous pass. An empty collection makes everything true. |
| 2 | No raw identifier in user-visible output | Un-hydrated values shipping as data |
| 3 | Consumer enumeration on contract change | One side of a contract moving alone |
| 4 | Preview and execute produce the same request set | Dry-run lying about what will happen |
| 5 | One bad row does not abort a valid batch | Row-level failure escalated to call-level |
| 6 | Unconsumed capability renders disabled-with-reason | Gaps discovered as opaque runtime errors |
| 7 | No two modules answer the same question from separate hardcoded lists | Divergent guess lists surfacing as blanks |

Build **1 and 2 first.** They are cheap, they generalize across every project,
and between them they catch most of what looks like data but is a defect.

## Coverage targets

Percentages are a poor target — they reward testing what is easy. Use these instead:

- **100%** of routes have an authorization test
- **100%** of adapters have four fixtures: happy, empty, rate-limited, malformed
- **100%** of money paths have a conservation property test
- **100%** of hash-producing functions have a committed golden fixture
- **Every** migration has been run forward and backward against a populated DB
- **Every** guard has been seen to fail once

## What to skip

Trivial getters, framework code, one-off scripts, and anything whose failure is
loud. Effort belongs where failure is **quiet**.

## Anti-patterns this framework has already hit

- **A guard depending on a tool that may be absent.** `guard.sh` used `jq`; without it the parse returned empty and the hook exited 0 — installed, enforcing nothing. Every guard needs a case asserting it **fails loud** when it cannot evaluate.
- **A fixture improvement deleting coverage.** Correcting a fake can remove the only case expressing a residual. When a fixture changes, diff the cases it expressed, not just its values.
- **A load-bearing number from a single source.** Two selectively-populated fields can fake a passing suite. Cross-check against a second source.
- **A scaffold nobody has watched fail.** Same defect one level up. A harness proves nothing until it has gone red.
