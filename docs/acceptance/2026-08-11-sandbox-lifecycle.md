# Sandbox lifecycle — teardown, rehydrate, measure, teardown · 2026-08-11

Full round trip of the `docs/SANDBOX.md` procedure, run end to end against
`roofadvisor/GHL-MCP`. The point of the exercise was to prove the procedure's
riskiest claim: **that sandbox copies are disposable, because the recipe
reconstitutes them.** Every clone created here has since been deleted; this
document and the SHA table below are what remain, and that is the design
working, not evidence being lost.

## Round trip

```
1. TEARDOWN ONE   remove ghl-mcp-audit-2          95M -> 47M, control untouched
2. REHYDRATE      clone current main as audit-3   47M, push disabled BEFORE anything else
3. MEASURE        audit-1 (control) vs audit-3    16-commit window
4. TEARDOWN ALL   symlink, then directory          94M -> 0, kit repo untouched
```

**Step 4 order is the load-bearing part.** `rm .sandbox` (bare, no trailing
slash) removed the link and left all 94M of the target intact — verified in the
same breath, before the second command ran. Only then did `rm -rf` on the real
path remove it. The reverse hazard is documented and was measured separately:
`rm -rf .sandbox/` **with** a trailing slash leaves the symlink and empties the
target.

**Push was disabled before the clone was read from, not after.** A fresh clone
of a client repo points at that client's live remote with push enabled; the
window between `git clone` and `remote set-url --push` is the only moment the
procedure is unsafe, so it is closed first and the failure observed:

```
git push --dry-run origin HEAD
fatal: 'DISABLED-sandbox-clone-no-push' does not appear to be a git repository
```

## Measurement — kit v1.22.2 held, target advanced 16 commits

`706d50bc` (audit-1's target) → `e42e9d9c` (current `main`, 2026-08-11T19:43).
Same kit both sides, so every difference is the repo.

| Gate | audit-1 | audit-3 | Δ |
|---|---|---|---|
| `check_catch_empty` | 64 | 64 | 0 |
| `check_guess_lists` | 150 | 150 | 0 |
| `check_log_hygiene` | 5 | 5 | 0 |
| `check_statelessness` | 1 | 1 | 0 |
| `check_raw_sql` | 0 | 0 | 0 |
| `check_pure_imports` | 0 | 0 | 0 |

Drift instruments, `BASE_REF=706d50bc`:

| Instrument | Result | Exit |
|---|---|---|
| `check_test_count` (C-08) | tests **6840 → 6897** (+57), zero deletions | 0 |
| `check_fixtures` (G-05) | **0 fixture-case decreases** | 1 — on I-02/I-03 only |
| `check_commits` (C-06) | **15/16 conventional**; one 111-char subject at `e42e9d9c` | 1 |

`check_fixtures`' non-zero exit is 5× I-02 (adapter missing the four-fixture set)
and 3× I-03 (missing `_meta.recorded_at`) — convention findings on a repo that
never adopted the convention, informational exactly as audit-2 classified them.
The drift measure inside that gate, G-05 case decreases, is clean.

**Verdict, now over 16 commits rather than audit-2's 12: growth without erosion.**
Every defect count held identical while the test suite grew by 57 cases and no
fixture case was deleted. No new debt entered any measured class.

**A gate caught its own author again.** The single C-06 violation is the current
HEAD commit — a 111-character subject, 11 over the ceiling. Same shape as
audit-1's over-long subjects being the only violations in that window.

## Recipes — everything above is reconstructible

Remote for all three: `https://github.com/roofadvisor/GHL-MCP.git`

| Name | SHA | Branch | Frozen at | Role |
|---|---|---|---|---|
| `ghl-mcp-audit-1` | `c5e2de9f` | `audit/f4d-kit-2026-08-10` | 2026-08-11T00:47 | control, kit ~1.13 era |
| `ghl-mcp-audit-2` | `5f9bb5b2` | `audit/f4d-kit-2026-08-11` | 2026-08-11T11:51 | kit 1.22.0 re-audit |
| `ghl-mcp-audit-3` | `e42e9d9c` | `main` | 2026-08-11T19:43 | current main, this run |

```bash
SB=/Users/ian-ra/code-projects/f4d/f4d-plugin-dev-sandbox
git clone https://github.com/roofadvisor/GHL-MCP.git "$SB/<name>"
git -C "$SB/<name>" remote set-url --push origin DISABLED-sandbox-clone-no-push
git -C "$SB/<name>" checkout <sha>
git -C "$SB/<name>" clean -fdX
```

A full clone is required rather than `--filter=blob:none` or a shallow one:
`check_test_count` and `check_fixtures` resolve `BASE_REF` through `git ls-tree`
and `git show`, so the baseline commit must be present in history.

## Kit state after teardown

```
git status          clean
tests               123 green (40 / 11 / 39 / 4 / 29)
gate scripts        4 clean
kit test-cases      13   <- unchanged throughout; never contaminated
.sandbox            absent, no dangling link
```

## What this establishes

1. **Disposability is real.** Two GB-scale clones were created, measured, and
   destroyed without losing a measurement. The recipe is the artifact.
2. **The teardown order is safe and the unsafe variant is known.** Link first
   with a bare `rm`, directory second.
3. **The isolation held for the whole lifecycle.** The kit's own test-case count
   read 13 before, during, and after — never once picking up the target's 6,897.
4. **Bounded, and stated:** this measured one repo across one window with the
   kit held constant. It says nothing about precision on a *different* codebase,
   which is why target selection skews toward well-built repos.
5. **One comparison caveat, surfaced by PR review:** audit-1 had been stripped
   with `git clean -fdX` and audit-3 was a fresh clone that was never built, so
   neither carried `.next`, `build/`, or `node_modules`. The comparison is
   therefore sound — both sides saw the same (absent) input — but it does **not**
   demonstrate that stripping is measurement-neutral in general. No before/strip
   and after/strip counts were taken, and the exclusion lists are not uniform:
   `check_fixtures` skips neither `build` nor `.next`, so it can count fixtures
   that `git clean -fdX` later removes. `docs/SANDBOX.md` now requires measuring
   before stripping rather than assuming it.
