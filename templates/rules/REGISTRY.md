# Rule Registry

Every rule this framework holds, with an ID, the layer it *should* live in, and
what enforces it **today**. A rule being unenforced is a tracked state, not a gap
in the documentation.

## Why this file exists

The failure it prevents: a rule is written down, everyone agrees it is correct,
nobody notices it is only prose, and it never fires. Documenting a rule and
enforcing a rule are two different acts. This registry keeps the difference
visible.

## Status vocabulary

| Status | Means |
|---|---|
| `HOOK` | A hook exits 2. Cannot be ignored. |
| `TEST` | A test fails the build. Cannot be ignored. |
| `GATE` | A CI job fails on it. Cannot be ignored. |
| `AGENT` | An audit agent reports it. Advisory — a human must act. |
| `LINT` | The linter or type checker catches it. |
| `PROSE` | Written down only. **Will eventually be ignored.** |
| `JUDGMENT` | Correctly prose — mechanising it would produce false positives. |

`PROSE` on a mechanisable rule is a **known debt**, and every one carries a
promote-when trigger. `JUDGMENT` is a finished state.

---

## Core

| ID | Rule | Should be | Today | Promote when |
|---|---|---|---|---|
| C-01 | Never commit `.env`, keys, credentials | HOOK | **HOOK** | done |
| C-02 | Never force-push a shared branch | HOOK | **HOOK** | done |
| C-03 | No destructive SQL from an agent session | HOOK | **HOOK** | done |
| C-04 | Verify passes before every commit | HOOK | **HOOK** (`done-check`) | done |
| C-05 | One canonical home per concept — no `V2`/`-final` variants | HOOK | **HOOK** (`rule-zero`) | done |
| C-06 | Branch per unit of work, conventional commits | LINT | PROSE | commitlint in CI — trivial, do it |
| C-07 | Change the smallest surface that solves the problem | JUDGMENT | JUDGMENT | — |
| C-08 | Never delete a test to make a build pass | TEST | PROSE | test-count-decrease check in CI |

## Guards

| ID | Rule | Should be | Today | Promote when |
|---|---|---|---|---|
| G-01 | A guard that passed on its first run has proved nothing — break it, see red, restore | JUDGMENT | PROSE + DoD | — (process, not code) |
| G-02 | Every hook has a fail-loud case in the harness | TEST | **TEST** (`tests/hooks_test.sh`) | done |
| G-03 | A guard that cannot evaluate its input must block, not allow | TEST | **TEST** | done |
| G-04 | Unguardable residuals are named explicitly | JUDGMENT | PROSE + DoD | — |
| G-05 | Improving a fixture must not delete a case it expressed | TEST | PROSE | fixture-case diff in `check_fixtures` |

## Silent degradation

The failure class that survives review. Highest-value column in this file.

| ID | Rule | Should be | Today | Promote when |
|---|---|---|---|---|
| S-01 | Assert a collection is non-empty before asserting over it | TEST | **TEST** (`templates/tests/`) | done |
| S-02 | Never render a raw identifier in user-visible output | TEST | **TEST** (`templates/tests/`) | done |
| S-03 | `catch → []` passes every downstream "is anything missing" gate | TEST | PROSE | lint rule banning empty-collection catch |
| S-04 | A new value/type/shape must fail a check, never degrade to a default | TEST | PROSE | exhaustiveness check at every enum boundary |
| S-05 | One canonical resolver per question — no two guess lists | GATE | PROSE | duplicate-constant-list scan in CI |
| S-06 | Do not infer what the source already stated | JUDGMENT | PROSE | — |
| S-07 | A pure function must not fetch | LINT | PROSE | lint rule: no IO import in `pure/` |
| S-08 | Cross-check load-bearing numbers against a second source | JUDGMENT | PROSE + DoD | — |
| S-09 | Account data read live; contract data may be a labelled constant | JUDGMENT | PROSE | — |

## Capability parity

| ID | Rule | Should be | Today | Promote when |
|---|---|---|---|---|
| P-01 | Contract change enumerates and aligns every consumer in the same change | GATE | **GATE** (`gates.yml`) | done |
| P-02 | An unconsumed capability renders disabled-with-reason | TEST | PROSE | project has a UI — then required |
| P-03 | Row-level problem blocks the row; only call-level fails the call | TEST | PROSE | project processes batches — then required |
| P-04 | Preview and execute produce the same request set | TEST | PROSE | project has a dry-run mode — then required |
| P-05 | Load and failure paths ship with the change | JUDGMENT | PROSE + DoD | — |

## Database

| ID | Rule | Should be | Today | Promote when |
|---|---|---|---|---|
| D-01 | Every FK has an index | GATE | **GATE** (`gates.yml`) | done |
| D-02 | No `NOT NULL` on a populated table in one step | GATE | **GATE** | done |
| D-03 | No drop/rename in the release that stops writing | GATE | **GATE** | done |
| D-04 | Money columns are `numeric`, never float | GATE | **GATE** | done |
| D-05 | Migrations reversible, or documented as not | TEST | **TEST** (`rollback_test`) | done |
| D-06 | No raw SQL in route handlers | LINT | PROSE | grep gate — cheap, do it |

## Integrations

| ID | Rule | Should be | Today | Promote when |
|---|---|---|---|---|
| I-01 | No test calls a live third-party API | GATE | **GATE** (`gates.yml`) | done |
| I-02 | Four fixtures per adapter: happy, empty, rate-limited, malformed | GATE | **GATE** | done |
| I-03 | Every fixture carries `recorded_at`; stale ones fail | GATE | **GATE** (`check_fixtures`) | done |
| I-04 | Timeout on every outbound call | GATE | **GATE** | done |
| I-05 | Retry only 429/5xx, with backoff and jitter | AGENT | AGENT | lint rule if it recurs |
| I-06 | Ingestion is idempotent on re-run | TEST | PROSE | required once a sync exists |
| I-07 | Documented per-field precedence when sources overlap | JUDGMENT | PROSE + spec | — |

## Contracts

| ID | Rule | Should be | Today | Promote when |
|---|---|---|---|---|
| K-01 | Types generated from the spec, never hand-written | GATE | **GATE** | done |
| K-02 | Consumers pin a contract version | GATE | **GATE** (`check_contract_pin`) | done |
| K-03 | No consumer more than one major behind | GATE | **GATE** | done |
| K-04 | Shared shape changes start in the contract repo | JUDGMENT | PROSE | — |

## Money

| ID | Rule | Should be | Today | Promote when |
|---|---|---|---|---|
| M-01 | `Decimal` or minor units; float banned in currency paths | GATE | **GATE** (`gates.yml`) | done |
| M-02 | Splits sum to exactly the total | TEST | PROSE | project moves money — then required |
| M-03 | Idempotency key on every charge, refund, payout | TEST | PROSE | project moves money — then required |
| M-04 | Never trust a client-supplied price | TEST | PROSE | project moves money — then required |

## Determinism

| ID | Rule | Should be | Today | Promote when |
|---|---|---|---|---|
| T-01 | Canonicalize (JCS) before hashing | TEST | PROSE | project hashes — then required |
| T-02 | Golden fixture per hash-producing function | TEST | PROSE | project hashes — then required |
| T-03 | Hash path changes get a new version, never an edited fixture | GATE | PROSE | fixture-immutability check |
| T-04 | No timestamps, uuids, paths, or floats inside a hashed payload | TEST | PROSE | project hashes — then required |

## Operations

| ID | Rule | Should be | Today | Promote when |
|---|---|---|---|---|
| O-01 | Repo rules load regardless of session cwd | HOOK | **HOOK** (`session-context`) | done |
| O-02 | Rollback step written before merge | JUDGMENT | PROSE + DoD | — |
| O-03 | Rollback rehearsed, not merely written | TEST | **TEST** (`rollback_test`) | done |
| O-04 | Production credentials never enter an agent session | HOOK | **HOOK** | done |
| O-05 | Structured logs; never log payloads, PII, or credentials | GATE | PROSE | secret-scan + payload-log grep |
| O-06 | Docs-only changes skip the full CI gate | GATE | **GATE** (path filters) | done |

---

## Reading this file

- **`PROSE` on a mechanisable rule is debt.** The promote-when column is its ticket.
- Several rules are `PROSE` because they only apply to some projects. `M-02` matters when the project moves money and is noise otherwise. Those promote at project setup, not globally — `/project-init` turns them on with the module.
- **`JUDGMENT` is finished.** Do not try to mechanize it; you will get false positives and people will disable the check.
- `/retro` updates this file. A rule that was violated gets its status re-examined before anyone restates it.
