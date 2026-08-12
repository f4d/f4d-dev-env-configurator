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
writes one report and pushes it. A sandbox run writes nothing and **must not be
able to push at all**. Do not let a convenience added here leak into that.

---

## Why real repos, and which ones

Synthetic fixtures prove a gate *runs*. Real repos prove the two properties that
decide whether a gate survives contact with a project:

| Target quality | Proves | Failure it catches |
|---|---|---|
| **Well-built** (most targets) | the gate stays **quiet** — precision | a gate that cries wolf on good code |
| **Defect-rich** (keep at least one) | the gate **finds** — recall | a gate that misses the real thing |

**Skew the sandbox toward good codebases.** A gate that fires 147 times against
excellent code is a broken gate, not a broken repo — and by the kit's own A8 law
a noisy gate gets disabled, after which it protects nothing. Precision is the
harder property and the one that decides adoption, so most targets brought in
should be code you'd be happy to have written.

Good targets pay a second dividend the defect-rich ones cannot: **they are a
source of conventions worth adopting**, not just findings to catch. A mature repo
that solved a problem well is a rule candidate — and that discovery is worth more
than another confirmed defect. Read them for what they do right, not only for
what the gates flag.

Keep at least one known-messy target anyway. Without it, recall is unmeasurable
and every gate looks perfect.

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

Every check in `/project-audit` reads source files, so all of them work on a
stripped clone and return byte-identical results — the scanners skip
`node_modules`, `dist`, and `.next` regardless.

**One exception:** `VERIFY: PASS` requires actually running the target's build
(`npm run verify`). That needs `npm install` first. Run it only when you intend
to re-prove that specific line.

---

## Multiple versions

The point of more than one copy is the delta: same gates, two snapshots, and the
difference is the measurement. Name them `<repo>-<n>` in age order and record
what each one *is* — a clone with no recorded SHA is not a control, it is
2 GB of ambiguity.

| dir | SHA | branch | frozen at | role |
|---|---|---|---|---|
| `ghl-mcp-audit-1` | `c5e2de9f` | `audit/f4d-kit-2026-08-10` | 2026-08-11T00:47 | control — never advance |
| `ghl-mcp-audit-2` | `5f9bb5b2` | `audit/f4d-kit-2026-08-11` | 2026-08-11T11:51 | current |

Both remotes are `https://github.com/roofadvisor/GHL-MCP.git`.

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

Baseline at kit v1.22.2, both snapshots:

| gate | audit-1 | audit-2 |
|---|---|---|
| `check_catch_empty` | 64 | 64 |
| `check_guess_lists` | 150 | 150 |
| `check_log_hygiene` | 5 | 5 |
| `check_statelessness` | 1 | 1 |
| `check_raw_sql` | 0 | 0 |
| `check_pure_imports` | 0 | 0 |

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
git clone --filter=blob:none https://github.com/roofadvisor/GHL-MCP.git "$SB/ghl-mcp-audit-1"
git -C "$SB/ghl-mcp-audit-1" remote set-url --push origin DISABLED-sandbox-clone-no-push
git -C "$SB/ghl-mcp-audit-1" checkout c5e2de9f
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
