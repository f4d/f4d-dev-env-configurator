# BACKLOG — f4d-kit

**Last updated:** 2026-08-11 · **Version shipped:** 1.22.2 · **Status:** all validation green (24/24 hooks, self-scans clean, all workflows parse)

> **Resume protocol.** If a session ends mid-work: read this file top to bottom,
> then `git log --oneline -5` to see where the last one stopped. Every item below
> is self-contained — ID, why it matters, what to build, how to know it's done,
> and which files it touches. Pick the top unstarted item in the priority list.
> Do not re-derive the reasoning; it is written down here.

---

## 0 — Current state

**Built and validated (as of 2026-08-12):**

| Surface | Count | Notes |
|---|---|---|
| Skills | 15 | repo-builder, org-profile, project-init, project-audit, framework-upgrade, promote-rule, notion-sync, new-module, new-integration, contract-first, work-intake, write-spec, decision-record, ship-it, retro |
| Rules modules | 22 | incl. REGISTRY.md with **76** rules (G-06 added) |
| Hooks | 7 | guard, rule-zero, session-context, done-check, verify-record, format, _parse — **now actually armed in this repo**, see below |
| Gate scripts | 12 | fixtures, contract-pin, guess-lists, rollback, statelessness, commits, raw-sql, pure-imports, catch-empty, log-hygiene, test-count, **companions** |
| Agents | 4 | schema-reviewer, integration-auditor, contract-drift-checker, verify-runner |
| Verify command | 1 | `scripts/verify.sh` — the kit had none until 2026-08-12, while `/project-audit` demanded one of every repo it audits |
| Process docs | 9 | LIFECYCLE, DEFINITION, CADENCE, ENFORCEMENT, TEST_STRATEGY, + templates |
| Framework ADRs | 3 | plugin distribution, GitHub over Linear, registry-over-enforce-all |
| Tests | **144** | hooks (43) + render_registry (11) + gate_trio (39) + statelessness (4) + conformance (32) + companions (18) |
| CI | 2 workflows | `gates.yml` (PR) + `main-verify.yml` (push to master) — the kit ran none of its own gates until 2026-08-12 |

**Rule status:** 44 mechanically enforced · 8 tracked debt with triggers · 13 judgment · rest scaffold/agent. (S-04 honestly re-opened in 1.22.2: an unused helper enforces nothing — its promote-when is now toolchain lint integration.)

### What changed on 2026-08-12 — read this before trusting anything above

Four things the kit demanded of every project but had never applied to itself
were closed. Each was found by *doing* the thing, not by reading the docs.

- **The kit now runs its own gates.** `.github/workflows/` did not exist; zero
  commits had ever touched it. `check_commits.py` and `check_test_count.py`
  need `BASE_REF` and had therefore never executed once against this repo.
- **The kit is installable.** `.claude-plugin/marketplace.json` did not exist,
  so every documented install path failed with `Marketplace file not found`.
  Proven working now: `claude plugin marketplace add ./` then
  `claude plugin install f4d-kit@f4d`.
- **The kit's own hooks are armed.** They had never fired here — no
  `.enforcement-log`, no `.session-log`, ever. Wiring them exposed two live
  bugs (see A18).
- **A single verify command exists** — `scripts/verify.sh`, which is also what
  makes `done-check.sh` satisfiable in this repo.

**Installed state:** f4d-kit is installed as a plugin (`f4d-kit@f4d`, scope
user) from the local marketplace. Because the marketplace source is a local
`./` path, `$CLAUDE_PLUGIN_ROOT` resolves to **this working repo**, not to the
versioned cache copy — so edits here are live in the installed plugin. A
consumer installing from GitHub instead gets
`~/.claude/plugins/cache/f4d/f4d-kit/<version>/`. Do not mistake that for a bug.

---

## 1 — Blocked on Ian (not code)

| ID | Item | Detail |
|---|---|---|
| **B-01** | Notion writes rejected | Three attempts to create `Engineering HQ — All Companies` + Work DB returned "No approval received" — nothing was created, nothing archived. Check the Notion connector has **write** access, or look for a pending approval dialog. Once cleared: create the HQ page, the Work DB per `templates/notion/WORK_DB_SCHEMA.md` (incl. `Company` + `Hub Mode`), all 9 views, seed `Company` options (Rezon8, F4 Digital, Brand Torus, RoofAdvisor, Personal), and archive the 4 legacy Trello boards. |
| **B-02** | Brand Torus repo path | Container cannot see `/Users/ian/GitHub/`. Need: `ls -d ~/GitHub/*brand* ~/GitHub/*torus*` output. Then `/project-audit` must run from inside that dir in Claude Code on desktop. |
| ~~B-03~~ | ~~Push the kit~~ | ✅ Done 2026-08-10 — published as `f4d/f4d-dev-env-configurator` (private). Docs updated to reference the real slug; the plugin/product name stays `f4d-kit`. |
| **B-04** | Secrets | Org-level: `CLAUDE_CODE_OAUTH_TOKEN` (via `claude setup-token`), `NOTION_TOKEN`. Org variable: `NOTION_WORK_DB` (**data source** id, not database id). |
| **B-05** | External Agents waitlist | Notion alpha. Free. Collapses two systems into one if it ships. |

---

## 2 — Architecture findings, open

Full reasoning in `docs/ARCHITECTURE_REVIEW.md`. Condensed to actionable form here.

### A4 — Interview is not resumable · ✅ built 1.11.0, **acceptance proven 2026-08-11**

Kill/re-run protocol executed against v1.16.0 in a scratch repo — both
done-when criteria MET with SHA-verified no-duplication, plus the commit-step
re-entry, delete-on-success-only, and P-04 plan/execute parity. Artifact with
verbatim evidence: `docs/acceptance/2026-08-11-a4-a5-acceptance.md`. Honest
bound recorded there: single-agent single-session run; a fresh-session
interactive run remains the gold proof; rich-scaffold Step-4 verify is O4.

---

### A2 — Registry duplicated per project · ✅ built in 1.15.0 (A9 closed with it)

Shipped 2026-08-11: projects hold `.claude/rules/manifest.json`
(`{"rules": [...], "overrides": {...}}`); rule text and status live only in the
plugin registry; `scripts/render_registry.py` renders the project view on demand
and `--validate` fails on any broken reference. `upgrade.py` reconciles: new
plugin rules surface as candidates (adoption is a decision, not a sync), a
committed project `REGISTRY.md` flags as `STALE-REGISTRY`, and broken manifest
refs exit 1. `REGISTRY.md` now states ID permanence (A9): supersede with a new
ID, never renumber. Proofs: `tests/render_registry_test.sh` — 11 cases, every
fail-loud path seen red (unknown ID, override-on-unheld, empty rules, unknown
key, missing/unparseable inputs, duplicate IDs both sides); live `upgrade.py`
red/green exit-code check. Done-when met: no project `REGISTRY.md`, rendered
view reproduces the stored shape, unknown ID fails the audit.

---

### A10 — No measurement of which rules fire · ✅ built in 1.17.0

Every deny logs `timestamp<TAB>rule_id<TAB>detail` to `.claude/.enforcement-log`
via a shared `log_deny` in `_parse.sh` whose hard property is proven in the
harness: telemetry can never change control flow — an unwritable log still
exits 2. Denies tagged: C-01 (secrets ×3), C-02 (force-push), C-03 (destructive
SQL), C-05 (rule-zero), G-03 (parse failure ×2), and three **UNREGISTERED**
denies (broadcast, mainnet RPC, rm -rf) — the guard enforces rules the registry
holds no row for; the fire report flags them as an honesty gap to resolve.
`session_report.py` prints fire counts on every path (including no-session-log)
with malformed-line disclosure; `/retro` cites the counts. Done-when met.

---

### A5 — Scaffolder has no dry run · ✅ built in 1.12.0

Shipped 2026-08-10: `--plan` runs the same decision path through Step 2, prints
the full plan (files AND non-file side effects), writes nothing — state stays in
memory; persisting it for a later resume is an explicit end-of-plan offer
(1.13.1). RETROFIT defaults to `--plan` first. **Proven 2026-08-11** with the
A4 acceptance run: zero writes after `--plan`, and the predeclared plan
file-list matched `git ls-files` exactly (P-04). Same artifact.

---

### A13 — ST-01 fires on import-time-populated registries · ✅ built in 1.17.1

Option (b), and the boundary is stated honestly: the scanner matches declaration
lines and cannot see cross-file call-site timing, so the sanctioned exception is
a **reviewed annotation** — `stateless-ok import-time registration — <cite the
call-site check>` — documented in `statelessness.md` § *Import-time registries*
and pointed at by the ST-01 finding message. Unannotated declarations fail
regardless of mutation timing (that IS the mechanism); the annotation is a claim
a reviewer verifies. 4-case harness: unannotated red, annotated green, no
blanket allow (line-scoped), message cites doctrine. Bare-annotation enforcement
deliberately stays audit-level — changing the scanner would fail existing
scaffolds' annotations.

---

### A15 — session-context.sh: retire or re-justify · ✅ decided in 1.17.2 — re-scoped, kept

**Evidence:** scratch repo, sentinel rule in `.claude/rules/`, no hook, no
`settings.json`; headless `claude -p` on **2.1.220** returned the sentinel
phrase exactly. Auto-load holds on the deployed CLI.

**Decision:** re-scope, keep. Primary job: **session telemetry**
(`.claude/.session-log` — the evidence layer session_report.py, /retro, and
/promote-rule run on; retiring the hook retires the evidence). The rules-index
injection stays as redundant defense-in-depth for older CLIs and
`--setting-sources` exclusions, and is never to be cited as the reason rules
load. All doctrine sites updated with the evidence.

---

### A17 — guess-list gate misses object-member lists · **low** · effort S

**Why:** re-audit measurement (2026-08-11) — `check_guess_lists` matches
string-literal collections only; GHL-MCP's six-file `CUSTOM_OBJECTS`
replication (object members with repeated key values) passes clean. The
highest-value S-05 instance found by agents is invisible to the S-05 gate.

**Build:** extend the heuristic to object-array literals — fingerprint on the
sorted values of a recurring key (e.g. `objectKey`) across 2+ files. Red-green
against the GHL-MCP pattern.

**Files:** `scripts/check_guess_lists.py`

---

### A18 — scaffolded repos have a DEAD enforcement layer · **CRITICAL** · effort M

**Why:** `${CLAUDE_PLUGIN_ROOT}` does **not** resolve inside a project's own
`.claude/settings.json`. A hook command referencing it is **skipped entirely** —
not run with an empty value. `/project-init` writes exactly that form
(`skills/project-init/SKILL.md:191`), so **every repo this kit has ever
scaffolded has non-functional hooks**: no secrets guard, no rule-zero, no
done-check, no session telemetry. The GHL-MCP audits recommended adopting that
layer; it would not have worked.

Measured 2026-08-12 on CLI 2.1.220, in a project's `.claude/settings.json`:

| Path form | Fires? | `$CLAUDE_PLUGIN_ROOT` |
|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}/hooks/x.sh` | **no** | — |
| absolute path | yes | — |
| repo-relative (`hooks/x.sh`, `.claude/hooks/x.sh`) | yes | — |
| plugin-declared `hooks/hooks.json` | yes | **resolves** |

Isolated with a control: a literal command in the identical position fired,
while a variant that wrote to a marker file *before* touching the variable
produced no output at all — so the hook never executed.

The irony worth preserving: `guard-local.sh` (A11's "fallback floor") uses a
relative path and is therefore **the only guard that has ever worked in a
scaffolded repo**. The fallback works; the primary never did.

**Build:** decide the delivery mechanism, then change what `/project-init`
emits. Options, with what each costs — measured, not guessed:

- **Absolute paths — ruled out.** The install path embeds the version
  (`~/.claude/plugins/cache/f4d/f4d-kit/1.22.2`), so the next release points
  every project at a directory that no longer exists. Silent death everywhere
  at once — the exact A11 shape.
- **Copy hooks into `.claude/hooks/`, reference relatively.** Works today
  (guard-local.sh proves it). Cost: copies drift, so `upgrade.py` must manage a
  new file class with the same FRAMEWORK/LOCAL/CONFLICT adjudication as rules.
- **Plugin-declared `hooks/hooks.json` + a per-repo opt-in check inside each
  hook** (recommended). The only form where the variable resolves; hook code
  lives in the plugin so it updates with the plugin, and nothing is copied into
  the target. Scope is global, so each hook must exit 0 on its first lines
  unless the repo opts in — key it on `.claude/.framework-state.json`, which
  `/project-init` and `upgrade.py` already write. Costs: a short-lived
  subprocess per matched tool call in *every* repo (guard.sh matches
  `Bash|Read|Edit|Write`), and a global blast radius that raises the bar on the
  fail-loud tests.

Whatever lands, prove it with a fired guard in a scaffolded repo — an
`.enforcement-log` entry, not a passing unit test.

**Files:** `skills/project-init/SKILL.md:191`, `hooks/hooks.json` (new),
`scripts/upgrade.py`, `templates/scaffold/guard-local.sh`, `hooks/*.sh`

---

### A19 — `/project-init` never ships the gates or the secrets preflight · **high** · effort S

**Why:** scaffold step 10 names `verify.yml`, `claude.yml`,
`claude-code-review.yml`, `notion-sync.yml`. Cross-checked against
`templates/github/`:

| Workflow | Template exists | Named in step 10 |
|---|---|---|
| `verify.yml` | **no** | **yes** — scaffolder told to write a template that isn't there |
| `gates.yml` | yes | **no** — the registry gates never install |
| `preflight.yml` | yes | **no** — the secrets scan never installs |

So every scaffolded repo gets Claude review and Notion sync but **not** the two
workflows that enforce the registry. That is a live §7.6 violation in the
product, and the likeliest reason the GHL-MCP audits kept finding
"enforceable-but-prose". Note `templates/scaffold/verify.yml.tmpl` does exist —
step 10 may simply be naming the wrong path.

**Build:** correct step 10 to copy `gates.yml` and `preflight.yml`, resolve the
`verify.yml` reference against `templates/scaffold/verify.yml.tmpl`, and add a
conformance assertion that every workflow step 10 names actually exists.

**Files:** `skills/project-init/SKILL.md:195-197`, `tests/conformance_test.sh`

---

### A20 — the agents are scaffolded but not selectable, and never audited · **medium** · effort S

**Why:** three gaps found 2026-08-12:

1. The interview's plan preview lists `AGENTS: contract-drift-checker,
   schema-reviewer, integration-auditor` (`SKILL.md:133`) — **`verify-runner` is
   missing**, though `LIFECYCLE.md:77` ("Anything"), `CADENCE.md:10` ("Per PR")
   and `ship-it/SKILL.md:21` ("Always") all call it unconditional. The always-on
   agent is the one absent from the plan the user approves.
2. Nothing defines *which* agents are "selected". Step 7 says "only the selected
   agents", but unlike modules — which have explicit `Q8 = yes → livesystem`
   mappings — agents have no selection rule at all.
3. `/project-audit` never checks agent presence. A repo can lose its agents and
   no audit notices. The A11 shape again.

**Files:** `skills/project-init/SKILL.md:133,190`, `skills/project-audit/SKILL.md`

---

### A21 — six scanners duplicate the SKIP tuple `_common.py` exists to hold · **medium** · effort S

**Why:** `scripts/_common.py` exists *because* `check_guess_lists.py` flagged
`git rev-parse --show-toplevel` duplicated across four scripts — its docstring
cites S-05, "extract one dependency-free leaf both sides import, never copy".
Only `check_statelessness.py` imports `SKIP_DIRS`. Six others define their own
near-identical `SKIP` tuple, and they disagree: only statelessness and
guess-lists filter dot-directories; `check_test_count.py` skips just
`.git`/`.venv`/`.next` by exact name; `check_fixtures.py` uses a substring match
and excludes neither `build` nor `.next`.

Measured consequence: 80 real files in a dot-prefixed directory took the kit's
own counted test cases from 13 to **345**, because `check_test_count` walked in
while other gates did not. The scanners do not agree on what the repo is.

**Build:** consolidate onto `_common.SKIP_DIRS`, extending it where a scanner
genuinely needs more (raw_sql's migrations/db/sql) via a documented extension
rather than a copy. Make dot-directory handling consistent and deliberate. Add a
test asserting every scanner agrees on one fixture tree.

**Files:** `scripts/_common.py`, `scripts/check_{catch_empty,log_hygiene,pure_imports,raw_sql,guess_lists,test_count,fixtures}.py`

---

### First live test — executed 2026-08-10, findings folded back

Target: `roofadvisor/GHL-MCP` on a scratch clone; deliverable is their PR #1042
(24 findings, 15 danger-annotated proposals; VERIFY green). Kit-side outcomes:
ST-01 false positive → **A13**; audit skill assumed a scaffolded repo → **absent
mode + adoption-recommendation shipped in 1.14.0**; `session_report.py`'s no-log
fallback behaved to spec; the report-document contract (dedicated branch, never
pushed unasked) held in practice. Six PR-review findings on the shipped text →
fixed in **1.13.1**. Review of the audit document itself then caught the kit's
**load-path doctrine stating a false claim** (subdir sessions DO load a root
`CLAUDE.md`; the modules are what never load) — corrected across seven sites in
**1.14.1**, plus a no-markers rule for committed reports. Still owed from the
test: the A4/A5 kill/re-run acceptance proof.

---

### A6 — Hook precedence unspecified · ✅ built in 1.19.0, evidence-backed

Empirical three-run protocol on CLI 2.1.220 (control + blocker-first +
blocker-second): any hook exiting 2 blocks in BOTH orders; a passing hook never
overrides. Contract + design consequence (hooks must be independent) in
`ENFORCEMENT.md` § *Hook precedence*; artifact with the runnable protocol in
`docs/acceptance/2026-08-11-a6-hook-precedence.md`. Honest bound: the bash
harness cannot test harness-level aggregation — the artifact's protocol IS the
test (minutes to re-run); cross-source merge is docs-based with the same
aggregation semantics empirically anchored.

---

### A11 — Plugin absence silently removes all guards · ✅ built in 1.20.0

`templates/scaffold/guard-local.sh`: self-contained (own parser, no shared
libs, no telemetry by design — zero dependencies that could take it down too),
covering C-01 secrets + C-02 force-push + G-03 fail-loud. `/project-init`
copies it into the repo and double-wires it alongside the plugin guard (safe
per A6). `/project-audit` asserts presence/executable/wired AND plugin version
matches the recorded framework state. 4 harness cases red-green.

---

### A9 — Rule IDs have no permanence guarantee · ✅ closed with A2 in 1.15.0

`REGISTRY.md` § *Reading this file* now states permanence (supersede with a new
ID, never renumber); `render_registry.py --validate` and `upgrade.py` fail on
any reference to an ID that does not exist.

---

### A22 — notion-sync templates: five review findings, all real · ✅ fixed in 1.23.1

The automated PR reviewer found five defects across `templates/github/claude-code-review.yml`,
`templates/github/notion-sync.yml`, and `scripts/notion_sync.py` on the
companycam-ghl-integration PR — the first review these three canonical
templates got after being copied byte-identical into three live RoofAdvisor
repos (GHL-MCP, AR-AP, companycam-ghl-integration). `scripts/notion_sync.py`
had never had a test; `tests/notion_sync_test.sh` is its first (14 checks,
wired into `scripts/verify.sh`'s harness loop).

**1 — draft→ready-for-review never triggered review.** `claude-code-review.yml`'s
job already gates on `github.event.pull_request.draft == false`, but `types:`
was `[opened, synchronize]` — `ready_for_review` is a distinct action, not a
`synchronize`, so marking a draft ready with no further commit created no
workflow run at all (the `if:` never even evaluates; there's no run to skip).
Added `ready_for_review` to `types:`. Verified against the actual parsed YAML,
not assumed — PyYAML's SafeLoader resolves the bare `on:` key to the boolean
`True` under YAML 1.1 (confirmed empirically first: `list(doc)` on the
unmodified file prints `['name', True, 'permissions', 'jobs']`, no string
`"on"` at all). Pre-fix `doc[True]["pull_request"]["types"] == ['opened',
'synchronize']`; post-fix includes `ready_for_review`, `opened` and
`synchronize` unchanged.

**2 — PR and issue events for the same work item raced.** `notion-sync.yml`'s
concurrency group was ``notion-sync-${{ github.event.issue.number ||
github.event.pull_request.number }}``. A merge that closes a linked issue
fires both `pull_request.closed` (group `notion-sync-45`) and `issues.closed`
(group `notion-sync-12`) — different keys, no serialization between them,
both able to write the same Notion row concurrently. Changed to a repo-wide
key: `notion-sync-${{ github.repository }}`. Per finding guidance, resolving
a PR's linked issue number at the YAML-trigger level would need an API call
concurrency groups can't make, so this serializes the whole repo instead of
attempting per-issue keys — deliberately not over-engineered; the workflow is
issue/PR events only, low-volume, losing per-issue parallelism costs nothing
real.

**3 — the serious one: PR events corrupted the linked issue's own fields.**
Traced fully, as asked, rather than taken on faith. `OWNED` (line 34 pre-fix)
lists the fields this sync may write but is **never referenced anywhere else
in the file** — decorative, not enforced; that is not where the bug lives.
The bug is in `main()`: GitHub's `pull_request` payload carries no top-level
`issue` key, so every PR event built a *synthetic* issue from the PR itself —
`title`, `created_at`, `labels`, all PR-sourced — and `build_props` sent that
unconditionally, **even when a real, already-correct row existed for the
issue**. A PR whose title, labels, or timestamp differ from its issue (the
normal case — "fix: null check" vs. "Users can't log in") silently overwrote
the issue's own `Title`/`Opened`/`GH Labels` on every open, and again on every
merge or close. Also found while tracing: `Title` is missing from the literal
`OWNED` set even though `build_props` writes it on every real `issues` event —
a documentation-accuracy gap, fixed alongside (one-line addition; `OWNED`
remains unenforced/decorative, that part is unchanged).

Fix splits the write path in two. `build_pr_mirror_props()` (new) handles a PR
event against an *existing* row: only `State`/`PR URL`/`Branch`/`Merged`/
`Commit`/`Synced` — never `Title`/`Opened`/`GH Labels`. For the *no row yet*
case — a PR is the first thing Notion has seen for its issue, a real scenario
(an issue predating the sync, or whose `issues` event sync failed or hasn't
fired yet), not hypothetical — `fetch_issue()` (new) fetches the real issue
from the GitHub API instead of fabricating one. `GITHUB_TOKEN` was already
threaded into the workflow's `env:` block and documented in this script's own
docstring, completely unused until now — strong circumstantial evidence this
was the intended path all along. `fetch_issue` soft-fails (`None`, logged) on
error rather than raising: nothing has been written to Notion yet at that
point, so a bad cross-repo reference or a flaky GitHub call skips one sync
instead of failing the whole job the way a Notion write failure does.

Red-then-green, captured directly — the harness was written and run against
the unmodified files first, not reconstructed after the fact. Pre-fix, the
corruption check failed with `issue-owned fields leaked into a PR-triggered
PATCH: ['Title', 'Opened', 'GH Labels']`, full payload showing the PR's own
title sitting in the `Title` property of issue #12's existing row. The
seed-from-PR check failed pre-fix with `Title='PR-side title for new
issue...', want 'Real GitHub Issue Title'` — the fabrication, caught
concretely. Both green post-fix; 3 more checks cover the existing-row PATCH
still carrying its legitimate PR-owned fields, and an unresolvable issue
reference skipping cleanly instead of fabricating a row.

**4 — closed-but-unmerged PRs stuck "In Review" forever.** `state = "Merged"
if pr.get("merged") else "In Review"` reached the `else` on any non-merged
PR, including abandoned ones — `pull_request.closed` fires on close-without-
merge too, same as on merge. The issue normally stays open and nothing else
ever touches the row again. New `pr_state()`: `merged` → `Merged`; `state ==
"closed"` and not merged → `Closed` — confirmed against the rest of the file
rather than assumed, by reading `build_props`'s existing `elif issue.get
("state") == "closed"` branch, which already uses `"Closed"` for a closed
issue with no PR; open and not merged → `In Review`, unchanged. Red pre-fix
(`got State='In Review', want Closed`), green post-fix; merged-PR and
open-PR cases re-checked as regressions, both still correct.

**5 — unbounded `urlopen()`.** No `timeout=` on the Notion call — a stalled
connection could occupy the job until the runner's own limit, and (per #2,
now repo-wide) block every other notion-sync run behind it. Added
`REQUEST_TIMEOUT = 30` and passed it to every `urlopen()` call, including the
new GitHub one in `fetch_issue()`. `except (urllib.error.URLError,
TimeoutError)` now logs and re-raises the same way `HTTPError` already did.
Confirmed pre-fix, mocked (no live outage needed): a `TimeoutError` from
`urlopen()` propagated with **no stderr diagnostic at all** (only `HTTPError`
was caught) while `urlopen()` itself received no `timeout` kwarg
(`timeout=None` observed directly off the mock call). Post-fix: `timeout=30`
observed on every call, and the diagnostic is logged before the exception
still propagates.

**Housekeeping surfaced along the way:** `check_catch_empty` (S-03) flagged
`fetch_issue`'s two new `except: ... return None` blocks — correctly, per its
own pattern, but both already log before returning, and the only caller
(`if not issue: return`) treats `None` as an explicit checked skip, never as
a found-but-empty issue. Annotated `catch-empty-ok`, matching the existing
convention, rather than restructured working code to dodge a gate. Not a
registry-tracked rule: `templates/rules/REGISTRY.md` grepped clean for
`notion`/`sync` (case-insensitive, whole file) except one unrelated hit —
I-06, generic ingestion-idempotency PROSE for scaffolded *projects*, not the
kit's own sync tooling. Confirmed rather than assumed; this is process-template
code the registry doesn't cover.

`scripts/verify.sh`: 147 → 162 assertions (`tests/notion_sync_test.sh` adds
15, now in the harness loop alongside hooks/render_registry/gate_trio/
statelessness/conformance/companions). All ten gate scripts clean. Top-level
summary table above left untouched deliberately — three other version-bump
PRs (1.22.3, 1.22.4, 1.23.0 ×2) are open concurrently against this same file;
reconciling all of them is one pass, not five.

**Independent check:** ran `integration-auditor` against the diff before
opening the PR (both external calls this file makes — Notion and the new
GitHub fetch — are exactly its remit). It confirmed timeout coverage is
complete and correct on both calls, the `call()`-raises vs.
`fetch_issue()`-soft-fails asymmetry is deliberate and correct (raise
wherever silently continuing could take the wrong branch — e.g. `find_row`
failing closed would misroute into the create path and duplicate a row;
soft-fail only where the caller's response to `None` is a true no-op), and
vendor shapes stay contained to this file. Two things came out of it and were
applied directly: `fetch_issue`'s own `urlopen()` timeout had no dedicated
test (only asserted indirectly through `main()`, which didn't check the
value) — added; and `build_props`/`build_pr_mirror_props` duplicated the
identical `Merged`/`Commit` block — extracted to `pr_merge_fields()`, used by
both. One finding was real but deliberately not fixed here — logged as
**N-04** below rather than folded into this change.

---

## 3 — Registry debt (PROSE that should be mechanized)

From `templates/rules/REGISTRY.md`. Each already carries a promote-when trigger.
Use `/promote-rule <ID>`.

**Global — do these regardless of project:**

| ID | Rule | Target | Effort |
|---|---|---|---|
| C-08 | Never delete a test to pass a build | TEST (test-count-decrease check) | S |
| S-03 | `catch → []` trap | LINT (ban empty-collection catch) | M |
| S-04 | New value must fail a check, not default | TEST (exhaustiveness at enum boundaries) | M |
| O-05 | Never log payloads/PII/credentials | GATE (secret-scan + grep) | M |
| G-05 | Fixture edit must not delete a case | TEST (fold into `check_fixtures.py`) | M |

**Project-conditional — turn on with the module at `/project-init`:**

M-02/03/04 (money) · T-01..04 (determinism) · P-02/03/04 (capability parity) ·
ST-10..12 (statelessness) · I-06 (idempotent ingestion)

---

## 4 — Opportunities (not defects)

| ID | Item | Value |
|---|---|---|
| O4 | ✅ tier 1 built in 1.21.0 (`tests/conformance_test.sh`: workflows + rendered compose templates parse, executables +x, every registry section resolves as a manifest, every spec-referenced template exists). Tier 2 (behavioral, agent-run) specified in `docs/acceptance/O4-protocol.md` — owns full-spec parity, verify-green-on-empty per combo, and failing-verify-keeps-state; cadence: one rich combo per minor, all five before v2.0 | **The scaffolder is the least-tested component in a system whose premise is testing** |
| O5 | Extract the doctrine (`silent-degradation`, `guards`, `capability-parity`) as a portable artifact | Most valuable content, least tool-coupled; survives a move off Claude Code |
| O6 | Cross-project rule analytics | Fires everywhere → always-on. Never anywhere → delete. One repo only → local problem |
| O2b | `/project-audit` asks the *unanswered* interview questions on an existing repo | Turns retrofit into a partial interview (A4 built — unblocked) |
| O7 | Multi-platform delivery — core + per-platform adapters | The stated goal: let several agent platforms install a native plugin for setup and audit. See below; **O5 is its critical path** |

### O7 — multi-platform delivery (core + adapters)

**The goal (Ian, 2026-08-12):** multiple agent platforms should be able to
install a native plugin and interact with the kit "for setup and audit
purposes" — from a distributed enterprise team down to one person on a personal
project.

**What the split actually looks like.** Most of the kit is already portable; the
coupling is concentrated in one layer:

| Portable today | Claude-Code-specific |
|---|---|
| Doctrine — rules modules, REGISTRY, LIFECYCLE, process templates | `skills/*/SKILL.md` format |
| All 12 gate scripts (plain Python, zero Claude dependency) | `agents/*.md` subagent format |
| Templates — workflows, compose, PR/ADR/spec | `hooks/` event contract + JSON shape |
| The audit *method* | `.claude-plugin/` manifests, `settings.json` |

That is O5 restated with a deadline: extract the doctrine as a portable
artifact, then wrap it per platform. `superpowers` is a worked example in the
plugin cache — MIT, one repo shipping `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, a
`gemini-extension.json`, and adapter references for Codex, Gemini, Pi and
Antigravity.

**Claude Cowork — read the docs 2026-08-12, and this is the decisive constraint.**
Per support.claude.com/en/articles/13345190: Cowork "uses the same agentic
architecture that powers Claude Code, with no terminal required", and a Cowork
plugin is a bundle of **skills, connectors (MCPs), and sub-agents**.

**Hooks are not in that list.** So Cowork can host the kit's advisory half — 15
skills and 4 agents, which is exactly the *setup and audit* surface Ian named —
but it cannot host the enforcement half. On Cowork, "guards, not memos" is
necessarily memos.

That is not a reason to skip Cowork. It is a reason to be explicit about which
half goes where: **skills and agents are the portable interaction surface;
hooks are the enforcement surface and stay in whichever environment does the
actual coding.** A17-era doctrine says a rule delegated to something that cannot
enforce it is unenforced (G-06) — so a Cowork adapter must not claim enforcement
it structurally cannot deliver, and `/project-audit` running there must report
that limit rather than pass silently.

**Open, not yet checked:** whether Cowork can execute the Python gate scripts at
all ("no terminal required" suggests a different execution model). If it cannot,
the audit surface there is agent-driven inspection only, and its findings are
weaker than a gate run — which must be stated in the report, not glossed.

**Depends on:** A18. The hook-delivery mechanism has to be settled before the
adapter boundary can be drawn, because A18's answer determines whether hooks
travel with the plugin or with the project.

---

## 5 — Notion / integration follow-ups

| ID | Item |
|---|---|
| N-01 | Migrate sync to Notion Workers when syncs/webhooks leave beta, **or at the third repo** — whichever first. Full analysis in `templates/notion/SYNC_ARCHITECTURE.md`. Four invariants make it a swap not a rewrite. |
| N-02 | `hub+local` reconciliation is documented (`/notion-sync` Mode 5) but never exercised — no project uses the mode yet |
| N-03 | Work DB `Repo` select options must be added as each repo is wired; sync fails on an unknown option |
| N-04 | `scripts/notion_sync.py`'s `call()` has no retry/backoff on 429/5xx (A22, `integration-auditor`). Not "low volume justifies it" alone — `NOTION_TOKEN` is an **org-level** secret shared across every repo wired to the Work DB (≥3 today), and Notion rate-limits per-integration/token, not per-repo, so simultaneous activity across repos can plausibly 429 with no self-healing today. Real gap, not urgent yet (B-01 blocks the Work DB even existing). **If picked up:** retry only on a definitive 429/5xx response, never on `URLError`/`TimeoutError` where the outcome is ambiguous — and never blindly retry the `POST /pages` create without re-running `find_row()` first, or a retried create after an ambiguous timeout duplicates the row. |

---

## 6 — Priority order

```
NOW      A18  scaffolded repos have a DEAD enforcement layer   <- CRITICAL, blocks O7
         A19  /project-init never ships gates.yml/preflight.yml

         B-01 Notion approval    (blocked on Ian)
         B-02 Brand Torus path   (blocked on Ian)

NEXT     A20  agent wiring (verify-runner absent, no selection rule, never audited)
         A21  SKIP tuple dedup — the kit's own S-05 violation
         A17  object-member guess-list gate

SOON     O4   tier-2 combo runs — ALSO the acceptance test for A18+A19,
              since it is an end-to-end /project-init exercise. Run it after them.
         S-04 promotion: eslint switch-exhaustiveness-check / mypy

LATER    O7   multi-platform delivery (core + adapters) — needs O5, blocked on A18
         N-01 Workers migration — at 3rd repo or beta exit
```

**Why A18 is first.** Every scaffolded repo currently has non-functional hooks.
Until the delivery mechanism is settled, `/project-init` keeps producing repos
whose enforcement layer looks present and does nothing — and O7's adapter
boundary cannot be drawn without that answer.

**Why O4 moved.** It is an end-to-end `/project-init` run, so it verifies A18
and A19 rather than duplicating them. Running it first would only certify the
broken scaffolder.

---

## 7 — Working agreements carried forward

Do not re-derive these; they were settled in the design conversation.

1. **Every guard gets a red-then-green proof before it counts.** Break it, see it fail, restore. A guard that passed first run has proved nothing.
2. **Every guard needs a fail-loud case** — what happens when it cannot evaluate its input. Two real bugs were found this way (`jq` absence, `git diff HEAD` on untracked files).
3. **Document a rule immediately; track its enforcement status separately.** `PROSE` on a mechanisable rule is debt with a ticket, never a silent gap.
4. **Never promote a JUDGMENT rule.** False positives → check disabled → protects nothing.
5. **Evidence over recollection.** Run `session_report.py` before concluding a rule was ignored — it may never have loaded.
6. **The registry must stay honest.** Any row claiming HOOK/TEST/GATE must have that check actually wired. `/project-audit` verifies this.
7. **Local customizations survive upgrades.** Never resolve a CONFLICT by taking the framework wholesale.
8. **Rules budget ~400 lines per repo.** Pruning is as important as adding.
