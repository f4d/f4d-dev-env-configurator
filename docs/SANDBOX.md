# Plugin-dev sandbox — running the kit against real repos

## Purpose

**To improve the plugin — its skills, its agents, and its gates — on two axes:
effectiveness (does it find the real defects) and performance (what does finding
them cost).** Neither is measurable against a scaffold. Both are measurable
against a real repo held still.

The workflow this document defines:

| Step | What it buys |
|---|---|
| **Bring a repo in** | a real target, cloned and made unable to push |
| **Run the kit against it** | effectiveness — what the skills, agents, and gates actually catch |
| **Multiple versions, SHA table** | the delta — did a kit change raise recall, or just move numbers |
| **Disk** | keeping copies affordable enough to keep the control |
| **Teardown / rehydrate** | copies stay disposable, so the evidence is the recipe, not the files |

The measurement this exists to produce already paid for itself once: audit-1's
catch-empty family cost two ~130k-token agent sweeps; after mechanization the
same family ran in seconds, and two tuning rounds measured against the frozen
control took recall from 147 raw findings to 64 real ones with the idiom noise
removed. That number is only meaningful because a frozen copy let both kit
versions run against identical code. See `.sandbox/*/docs/f4d-audit-delta-*.md`.

## What this is not

**This is not the procedure for auditing a client project.** That one runs in
the client's own checkout and produces a report they receive.

The distinction matters because the two have opposite defaults. A client audit
writes one report and pushes it. A sandbox run **must not be able to push at
all**. Do not let a convenience added here leak into that.

### "Read-only" is true of scanners, not of `/project-audit`

Running the check scripts directly writes nothing. **Running `/project-audit`
does**: its contract requires a report at `docs/f4d-audit-<date>.md`, *"on a
dedicated branch when the repo has git"* (`skills/project-audit/SKILL.md:144`).
That is a commit and a branch — which moves `HEAD` off the pinned SHA.

**Never run `/project-audit` against a frozen control.** A control that has been
audited is no longer at the SHA the table claims, and nothing announces it. Run
it against a working copy instead — clone a second time from the same SHA if you
need both.

If you do audit a sandbox copy, capture the report out before resetting:

```bash
cp docs/f4d-audit-*.md /somewhere/outside/the/sandbox/
git checkout <pinned-sha>            # detach back to the recorded state
git branch -D <the-audit-branch>
git status --porcelain               # must be empty
```

The report belongs in the kit (`docs/acceptance/`) rather than in the clone —
the clone is disposable and the report is the evidence.

---

## Why real repos, and which ones

**Bring in good codebases, because good codebases are where new conventions come
from.** Developers develop; a repo that has been maintained well for years has
already solved problems this kit has not named yet. Reading it for what it does
*right* is the primary harvest — new rules, new test types, new gate ideas — and
that is worth more than another confirmed defect.

Findings are the secondary harvest. Synthetic fixtures prove a gate *runs*; real
repos prove the two properties that decide whether it survives contact:

| Target | Primary value | Also proves |
|---|---|---|
| **Well-built** (most targets) | practices worth systematizing | the gate stays **quiet** — precision |
| **Defect-rich** (keep at least one) | known-missed cases to tune against | the gate **finds** — recall |

Precision matters because a gate that fires 147 times against excellent code is a
broken gate, not a broken repo — and by the kit's own A8 law a noisy gate gets
disabled, after which it protects nothing. But precision is a check on the
harvest, not the reason to prefer good targets.

Keep at least one known-messy target anyway. Without it recall is unmeasurable
and every gate looks perfect.

### Where a harvested practice goes

A practice found in a good repo is a candidate, not a rule. Route it the same way
any other kit-ward discovery is routed:

| The practice is | Route to |
|---|---|
| Worth every repo having, mechanizable | rules module + a gate, on **by default** |
| Worth having, but project-shaped | a `/project-init` interview question — **offered, not imposed** |
| Already common, often missing | a **suggested add** in `/project-audit`, with its danger column |
| Good, but only makes sense there | nothing. Note it and move on. |

The last row is the discipline. §7.8 caps rules at ~400 lines per repo, and O6
states the test: *fires everywhere → always-on; one repo only → local problem.*

The standing cost is overfitting: tuning gates against one codebase shapes them
to that codebase. Treat sandbox findings as evidence, never as the specification.
When a gate changes because of a sandbox finding, the fixture that locks the
change in belongs in `tests/`, not here.

---

## Layout

```
/Users/ian-ra/code-projects/f4d/
├── f4d-dev-env-configurator/       ← the kit (this repo)
│   └── .sandbox  ──────────────┐   ← symlink, gitignored
└── f4d-plugin-dev-sandbox/  ◄──┘   ← real location, outside the kit's git repo
    ├── ghl-mcp-audit-1/            ← frozen control
    └── ghl-mcp-audit-2/            ← current
```

**The symlink is load-bearing, not cosmetic.** `os.walk()` does not follow
symlinks (`followlinks=False` is the default), so every kit scanner walks past
`.sandbox` without descending. That is what keeps a foreign repo from
contaminating the kit's own gate runs.

A plain directory — even a dot-prefixed one — does **not** work. Only
`check_statelessness.py` and `check_guess_lists.py` filter dot-directories;
`check_test_count.py` skips just `.git`, `.venv`, and `.next` **by exact name**,
and the rest carry their own duplicated `SKIP` tuples. Measured, with 80 real
files in a dot-prefixed real directory:

| kit's own test-case count | |
|---|---|
| baseline | **13** |
| with real `.probe-nested/` dir | **345** |
| with `.sandbox` symlink (2 GB reachable) | **13** |

Because the sandbox lives outside the kit's git repo entirely, a stray
`git add -A` can ingest at most a ~25-byte symlink. Nothing in the sandbox can
ever reach a commit, a push, or a CI transfer.

---

## Bringing a repo in

```bash
SB=/Users/ian-ra/code-projects/f4d/f4d-plugin-dev-sandbox
git clone https://github.com/<org>/<repo>.git "$SB/<name>"
```

Then, **before doing anything else**, cut the push path:

```bash
git -C "$SB/<name>" remote set-url --push origin DISABLED-sandbox-clone-no-push
```

Verify it actually holds — a guard you have not seen fail is not a guard:

```bash
git -C "$SB/<name>" push --dry-run origin HEAD    # must: fatal: does not appear to be a git repository
git -C "$SB/<name>" ls-remote --heads origin      # must still work — fetch stays available
```

Finally strip rebuildable bulk (see *Disk*, below).

---

## Running the kit against a sandbox repo

Every kit script resolves its target from the **process working directory** —
`scripts/_common.py` calls `git rev-parse --show-toplevel` with a cwd fallback.
So you `cd` into the target and invoke the kit's script by absolute path. The
plugin does **not** need to be installed for this:

```bash
KIT=/Users/ian-ra/code-projects/f4d/f4d-dev-env-configurator
export CLAUDE_PLUGIN_ROOT="$KIT"          # satisfies $CLAUDE_PLUGIN_ROOT refs in skills
cd "$KIT/.sandbox/<name>"
python3 "$KIT/scripts/check_statelessness.py"
```

`export CLAUDE_PLUGIN_ROOT` covers the two scripts that read it:
`render_registry.py` (`--plugin` defaults to it) and `upgrade.py` (`--plugin`
required).

### What a stripped clone can and cannot do

Every check reads source files, so all of them run on a stripped clone. Counts
are **stable for most scanners but not guaranteed for all** — the exclusion lists
are not uniform:

| Scanner | Skips `dist` | Skips `build` | Skips `.next` |
|---|---|---|---|
| `check_statelessness`, `check_guess_lists` | yes | yes | yes — via the `startswith(".")` filter, not `SKIP` |
| `check_catch_empty`, `check_log_hygiene`, `check_pure_imports`, `check_raw_sql` | yes | yes | **no** |
| `check_fixtures` | yes | **no** | **no** |

So `git clean -fdX` can remove input that `check_fixtures` was counting — a
fixture directory under `build/` or `.next/` disappears, and the before/after
counts differ for a reason that has nothing to do with the code.

**Measure before stripping, and record both numbers.** It costs one command and
it is the only thing that turns "stripping is measurement-neutral" from an
assumption into a fact for the target in front of you:

```bash
cd "$KIT/.sandbox/<name>"
for g in check_catch_empty check_log_hygiene check_statelessness check_fixtures; do
  echo "$g before: $(python3 "$KIT/scripts/$g.py" 2>&1 | grep -cE '^[[:space:]]+.*:[0-9]+')"
done
git clean -fdX
# ...re-run and compare. A difference is a finding about the scanner, not the repo.
```

A fresh clone that was never built has no `.next`, `build/`, or `node_modules` to
begin with, so this only matters for a clone you inherited or built in.

**One exception:** `VERIFY: PASS` requires actually running the target's build
(`npm run verify`). That needs `npm install` first. Run it only when you intend
to re-prove that specific line.

---

## Multiple versions

The point of more than one copy is the delta: same gates, two snapshots, and the
difference is the measurement. Name them `<repo>-<n>` in age order and record
what each one *is* — a clone with no recorded SHA is not a control, it is
2 GB of ambiguity.

**The sandbox is currently empty.** All three clones below were created,
measured, and destroyed on 2026-08-11 — the full round trip is recorded in
`docs/acceptance/2026-08-11-sandbox-lifecycle.md`. That is the procedure working:
the recipe is the artifact, the files are a cache.

| name | SHA | branch | frozen at | role |
|---|---|---|---|---|
| `ghl-mcp-audit-1` | `c5e2de9f` | `audit/f4d-kit-2026-08-10` | 2026-08-11T00:47 | control, kit ~1.13 era |
| `ghl-mcp-audit-2` | `5f9bb5b2` | `audit/f4d-kit-2026-08-11` | 2026-08-11T11:51 | kit 1.22.0 re-audit |
| `ghl-mcp-audit-3` | `e42e9d9c` | `main` | 2026-08-11T19:43 | current main |

All three remotes are `https://github.com/roofadvisor/GHL-MCP.git`.

Use a **full clone**, not `--filter=blob:none` or `--depth`: `check_test_count`
and `check_fixtures` resolve `BASE_REF` via `git ls-tree` and `git show`, so the
baseline commit has to be in history.

Measuring across them — counts are per-gate, and the formats differ, so count
deliberately rather than with one regex:

```bash
KIT=/Users/ian-ra/code-projects/f4d/f4d-dev-env-configurator
for d in ghl-mcp-audit-1 ghl-mcp-audit-2; do
  cd "$KIT/.sandbox/$d"
  echo "$d: $(python3 "$KIT/scripts/check_catch_empty.py" 2>&1 | grep -cE '^[[:space:]]+.*:[0-9]+')"
done
```

`check_guess_lists.py` prints file paths **without** line numbers under each
duplicated list, so the pattern above scores it 0. Count its list headers
instead: `grep -cE '^  \['`.

Baseline at kit v1.22.2, all three snapshots — kit held constant, so every
column difference would be the repo:

| gate | audit-1 | audit-2 | audit-3 |
|---|---|---|---|
| `check_catch_empty` | 64 | 64 | 64 |
| `check_guess_lists` | 150 | 150 | 150 |
| `check_log_hygiene` | 5 | 5 | 5 |
| `check_statelessness` | 1 | 1 | 1 |
| `check_raw_sql` | 0 | 0 | 0 |
| `check_pure_imports` | 0 | 0 | 0 |

Identical across a 16-commit window while the suite grew 6840 → 6897 tests with
zero deletions and zero fixture-case decreases. **A flat row is a result, not a
failed measurement** — it says no new debt entered that class.

The drift instruments need `BASE_REF` and measure the window rather than the
snapshot:

```bash
cd "$KIT/.sandbox/<name>"
BASE_REF=<baseline-sha> python3 "$KIT/scripts/check_test_count.py"
BASE_REF=<baseline-sha> python3 "$KIT/scripts/check_commits.py"
BASE_REF=<baseline-sha> python3 "$KIT/scripts/check_fixtures.py"
```

Read `check_fixtures`' exit code with care: it fails on I-02/I-03 convention
findings (missing four-fixture sets, missing `_meta.recorded_at`) that are
informational on a repo which never adopted the convention. The drift measure
inside it is **G-05 case decreases** — grep for that specifically.

---

## Disk

A full clone of a mature repo is mostly rebuildable output. Strip it with git's
own ignore list, which by definition removes nothing git tracks:

```bash
git -C "$SB/<name>" clean -ndX     # dry run — read this first
git -C "$SB/<name>" clean -fdX     # then do it
```

Measured on both GHL-MCP clones: **1.0 GB → ~47 MB each**, 2.1 GB → 95 MB total.
What remains is what matters — ~17 MB of `.git` and ~30 MB of tracked source.

Never use `git clean -fdx` (lowercase `x`). It removes untracked-but-not-ignored
files too, which on an audit clone can mean a report that was never committed.

---

## Teardown

Nothing here is precious — **every sandbox repo is reconstructible from its
remote**, which is why the SHA table above is the real artifact and the files
are just a cache.

Remove one copy:

```bash
rm -rf /Users/ian-ra/code-projects/f4d/f4d-plugin-dev-sandbox/<name>
```

Remove everything, kit untouched:

```bash
rm /Users/ian-ra/code-projects/f4d/f4d-dev-env-configurator/.sandbox   # the symlink ONLY — no -r
rm -rf /Users/ian-ra/code-projects/f4d/f4d-plugin-dev-sandbox
```

**The trailing slash is the trap, and it is not theoretical.** Measured on this
machine:

| command | symlink | target contents |
|---|---|---|
| `rm -rf .sandbox/` | **survives** | **deleted** |
| `rm .sandbox` | removed | intact |

`rm -rf .sandbox/` resolves the link and empties what it points at, then leaves
the link behind pointing at nothing — so the damage is done *and* looks
undone. Delete the link with a bare `rm` and no trailing slash, then remove the
real directory by its own path, in that order.

Rehydrate any row from the table in about 30 seconds:

```bash
SB=/Users/ian-ra/code-projects/f4d/f4d-plugin-dev-sandbox
git clone https://github.com/roofadvisor/GHL-MCP.git "$SB/ghl-mcp-audit-1"
git -C "$SB/ghl-mcp-audit-1" remote set-url --push origin DISABLED-sandbox-clone-no-push
git -C "$SB/ghl-mcp-audit-1" checkout c5e2de9f
git -C "$SB/ghl-mcp-audit-1" clean -fdX
```

---

## Non-negotiables

1. Push is disabled at clone time, before any other command, and the failure is
   observed once rather than assumed.
2. The sandbox lives outside the kit's git repo and is reached only through the
   gitignored symlink. Never a real directory inside the repo.
3. Every copy has a recorded SHA in the table above. Unrecorded copies get
   deleted, not kept.
4. Sandbox findings are evidence for changing a gate. The test that locks the
   change in lives in `tests/`, never in the sandbox.
5. After any sandbox change, re-run the kit's own verification ritual
   (`START_HERE.md`) and confirm the counts are unchanged. Contamination shows
   up there first.
