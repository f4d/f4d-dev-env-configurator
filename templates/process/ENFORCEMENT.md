# Enforcement

The organizing principle of this framework, and the one it most easily violates.

## Three layers, differing in whether they can be ignored

| Layer | Enforced by | Ignorable? |
|---|---|---|
| **Hooks** (`.claude/settings.json`) | The harness, before/after tool calls | **No** — it executes |
| **Tests** (verify, CI) | The test runner | **No** — it fails the build |
| **Skills** | Fire on task shape | Only by not invoking them |
| **Instruction files** (CLAUDE.md, rules) | Being read | **Yes — demonstrably** |

Anything load-bearing should be a hook or a test. Instruction files carry
reference and judgment, not enforcement.

## The load-path defect

*(Corrected 2026-08-11 — the first live test disproved this section's earlier
claim that subdirectory sessions load no repo-root files.)*

`CLAUDE.md` auto-loads with an **upward walk** from the directory a session
starts in — a root `CLAUDE.md` reaches a session started in `dist/` or
`packages/x/` just fine (verified live: a root `CLAUDE.md` loaded from a
session two directories deep). What does **not** auto-load, from anywhere:
`AGENTS.md`-style guides, and this kit's `.claude/rules/*.md` modules.

That is the real load-path defect: without help, every session — root or
subdirectory — gets **only `CLAUDE.md`**, never the rules modules; and a repo
whose operating guide lives in a file that doesn't auto-load has no loaded
rules at all. "The agent stopped reading the rules file" is still usually a
configuration defect rather than a discipline problem — the file it "ignored"
was never in context.

**The fix is `hooks/session-context.sh`**, a SessionStart hook that walks to the
repo root and injects the rules index into every session. It ships in this kit
and is wired by `/project-init`.

Corollary: **never diagnose a repeated instruction failure as inattention until
you have confirmed the instruction was actually in context.** Check the load path
first.

## Honest audit of this framework

Most of what f4d-kit ships is prose, and prose is the ignorable layer. Where each
rules module actually sits:

| Module | Mechanically enforceable | Currently enforced by |
|---|---|---|
| `keysafety` | Yes | **hook** — `guard.sh`, exit 2 |
| `core` (no force-push, no destructive SQL) | Yes | **hook** — `guard.sh` |
| Canonical home / no duplicate variants | Yes | **hook** — `rule-zero.sh` |
| Done-without-verify | Yes | **hook** — `done-check.sh` |
| `database` (FK indexes, unsafe migrations) | Yes | `schema-reviewer` agent — advisory, should become a test |
| `data-integration` (timeouts, retries, fixtures) | Yes | `integration-auditor` agent — advisory, should become a test |
| `contracts` (drift) | Yes | `contract-drift-checker` agent + CI gate |
| `silent-degradation` (empty-collection, raw ids) | **Yes — and not yet enforced** | prose. Highest-value gap. |
| `capability-parity` (consumer enumeration, parity) | **Partly — and not yet enforced** | prose |
| `money` (splits sum, no float) | Yes | prose — should be a lint rule + property test |
| `determinism` (golden fixtures) | Yes | prose — should be a committed fixture test |
| `guards` (red-then-green) | Partly | prose + Definition of Done |
| `api`, `python`, `typescript` style | Partly | linter where possible, else prose |
| `livesystem`, `dataprotection`, `observability` | Mostly judgment | prose, correctly |

**The rightmost column is the roadmap.** Every "prose" entry that is mechanically
enforceable is a known gap, not an accepted state.

## Rules that should become tests, in priority order

These are the checks that catch silent degradation — the failure class that
survives review because the output still looks plausible:

1. **Non-empty assertion** — any test iterating a collection asserts it is non-empty first. An empty collection makes every assertion vacuously true.
2. **No raw ids rendered** — a test that fails if an identifier appears in user-visible output.
3. **Consumer enumeration** — changing a shared contract fails CI until every consumer is touched in the same change.
4. **Preview/execute parity** — a dry run and a live run produce the same request set.
5. **Row vs call failure** — one bad row in a batch does not abort the batch.
6. **Unconsumed capability is visible** — a capability with no consumer renders as disabled-with-reason, not as an absent control.
7. **One canonical resolver** — no two modules answer the same question from separate hardcoded lists.

Each needs a **failing-then-passing** test proving the harness works before it is
populated. A scaffold nobody has seen fail is the same defect one level up.

## The rule this page exists to prevent

> Every one of these rules was already in force, and none of them fired,
> because they are prose.

When `/retro` finds a rule that was violated, the first question is not "how do
we restate it" — it is **"which layer should this have been in?"**
