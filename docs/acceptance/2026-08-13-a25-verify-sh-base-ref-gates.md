# A22 — `verify.sh` BASE_REF gating, red-then-green, 2026-08-13

Why this is a protocol document and not a `tests/*.sh` assertion: every existing
harness (`hooks`, `render_registry`, `gate_trio`, `statelessness`, `conformance`,
`companions`) is itself one of the six things `scripts/verify.sh`'s own
"harnesses" loop runs. `verify.sh` always operates on **its own containing
repo** (`KIT="$(cd "$(dirname "$0")/.." && pwd)"`), so the only way to exercise
its real end-to-end behavior is to run it against a full copy of the kit — and
adding that as a new harness *inside* `verify.sh`'s own loop would make
`verify.sh` call itself recursively. Same bound as A6: the harness cannot test
harness-level orchestration; this protocol is the test, re-runnable in minutes
against a disposable clone.

Setup used throughout: `git clone` this repo into a scratch directory so
nothing below touches real branch history.

## RED — bug confirmed, both gates, before the fix

**Scenario 1 — bad commit subject (C-06).** One commit on top of `master`:
`added some stuff without a conventional type prefix`. Direct invocation
confirms it is a real C-06 violation:

```
$ BASE_REF=master python3 scripts/check_commits.py
C-06 VIOLATIONS (1 of 1 commits):
  'added some stuff without a conventional type prefix'
      not conventional — expected `type(scope)?: subject`
exit=1
```

Pre-fix `verify.sh`, same branch, `BASE_REF=master` exported (harness loop
run with `env -u BASE_REF` as a control, so the harness-leak finding below
does not confound this reading):

```
$ BASE_REF=master bash scripts/verify.sh
...
[harnesses]  (total)  147 assertions   <- all clean, this is a control
[gate scripts]  ... all clean
[skipped locally (need BASE_REF — CI runs these)]
  check_commits            C-06
  check_test_count         C-08

[result]
  VERIFY PASSED
```

`BASE_REF` was set to a real, resolvable ref. `check_commits.py` was never
invoked. `gates.yml`'s own PR job would fail this exact commit.

**Scenario 2 — test count decrease (C-08).** Commit A adds
`tests/test_scratch_redgreen.py` (two `def test_` cases); commit B deletes it
with no `test-removal-ok:` reason. Direct invocation:

```
$ BASE_REF=<commit-A-sha> python3 scripts/check_test_count.py
C-08 VIOLATION: test count decreased 15 -> 13 against <commit-A-sha>.
exit=1
```

Pre-fix `verify.sh`, same branch, `BASE_REF=<commit-A-sha>` exported:

```
[harnesses]  (total)  147 assertions   <- control, all clean
[gate scripts]  ... all clean
[skipped locally (need BASE_REF — CI runs these)]
  check_commits            C-06
  check_test_count         C-08

[result]
  VERIFY PASSED
```

Same bug: `check_test_count.py` never ran despite a real, set `BASE_REF`.

## A second bug, found by the RED protocol itself

Running the RED scenarios *without* isolating the harness loop
(`BASE_REF=master bash scripts/verify.sh`, no `env -u`) produced `gate_trio
pass=38 fail=1` instead of `39/0` — one assertion flipped for a reason
unrelated to either scratch scenario. Isolated directly:

```
$ BASE_REF=master bash tests/gate_trio_test.sh 2>&1 | tail -2
FAIL: C-08 states not-evaluable without BASE_REF (expected exit 0, got 1)
pass=38 fail=1
$ env -u BASE_REF bash tests/gate_trio_test.sh 2>&1 | tail -1
pass=39 fail=0
```

`gate_trio_test.sh` asserts both "`BASE_REF` set" and "`BASE_REF` unset"
behavior for C-06/C-08 inside its own disposable repos, and does not itself
manage the variable — it inherits whatever its caller has exported. CI never
hits this because the harnesses job and the gates job run on separate
runners with independent environments. `verify.sh` runs everything in one
process, so the moment it started honoring a caller's `BASE_REF` (the whole
point of this fix), that same export would leak into the harness loop and
flip this assertion on every local run where `BASE_REF` happens to be set —
a false `VERIFY FAILED`, for a reason having nothing to do with the branch
being checked. Fixed in the same change: the harnesses loop now runs each
harness under `env -u BASE_REF`.

## GREEN — fixed `verify.sh`, same two branches

Scenario 1:

```
$ BASE_REF=master bash scripts/verify.sh
[harnesses]  (total)  147 assertions   <- unaffected: env -u BASE_REF fix holds
[gate scripts]  ... all clean
[base-ref gates (BASE_REF=master)]
  check_commits            FINDINGS
  check_test_count         clean

[result]
  VERIFY FAILED
exit=1
```

Scenario 2:

```
$ BASE_REF=<commit-A-sha> bash scripts/verify.sh
[harnesses]  (total)  147 assertions
[gate scripts]  ... all clean
[base-ref gates (BASE_REF=<commit-A-sha>)]
  check_commits            clean
  check_test_count         FINDINGS

[result]
  VERIFY FAILED
exit=1
```

## Control — the legitimate no-`BASE_REF` case is unchanged

```
$ env -u BASE_REF bash scripts/verify.sh      # fixed script, clean master
...
[skipped locally (need BASE_REF — CI runs these)]
  check_commits            C-06
  check_test_count         C-08

[result]
  VERIFY PASSED
exit=0
```

Two edge cases checked in addition to the non-negotiables:

- `BASE_REF=""` (exported but empty) — treated as absent, same skip message,
  `PASSED`. `[ -n "${BASE_REF:-}" ]` is false for an empty string, matching
  how `check_commits.py`/`check_test_count.py` already treat `.strip()` on an
  empty value as unset.
- `BASE_REF=origin/does-not-exist-anywhere` (set but unresolvable) —
  `check_commits.py` and `check_test_count.py` both fail loud (G-03) rather
  than silently passing; `verify.sh` correctly reports `VERIFY FAILED`. No
  special-casing was added for this in `verify.sh` itself — it falls
  straight through to the existing fail-loud behavior already built into both
  scripts.

## Bound

This protocol was run against a disposable clone of the kit at `master`
(2bde2e9). It was not re-run against a live GitHub Actions job — `gates.yml`'s
own invocation pattern (`python "scripts/$1"`, no args, `BASE_REF=origin/<base
branch>`, repo root) was read directly from `.github/workflows/gates.yml`
rather than re-observed in a live run, and `verify.sh` now reproduces it
(`python3` instead of `python`, matching this file's own existing convention
for every other gate script it runs — not a CI invocation this file already
diverges from in every other line).
