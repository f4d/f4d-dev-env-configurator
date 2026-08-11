# BACKLOG — f4d-kit

**Last updated:** 2026-08-11 · **Version shipped:** 1.14.0 · **Status:** all validation green (24/24 hooks, self-scans clean, all workflows parse)

> **Resume protocol.** If a session ends mid-work: read this file top to bottom,
> then `git log --oneline -5` to see where the last one stopped. Every item below
> is self-contained — ID, why it matters, what to build, how to know it's done,
> and which files it touches. Pick the top unstarted item in the priority list.
> Do not re-derive the reasoning; it is written down here.

---

## 0 — Current state

**Built and validated (v1.10.0):**

| Surface | Count | Notes |
|---|---|---|
| Skills | 15 | repo-builder, org-profile, project-init, project-audit, framework-upgrade, promote-rule, notion-sync, new-module, new-integration, contract-first, work-intake, write-spec, decision-record, ship-it, retro |
| Rules modules | 22 | incl. REGISTRY.md with 72 rules |
| Hooks | 7 | guard, rule-zero, session-context, done-check, verify-record, format, _parse |
| Gate scripts | 6 | fixtures, contract-pin, guess-lists, rollback, statelessness, upgrade |
| Agents | 4 | schema-reviewer, integration-auditor, contract-drift-checker, verify-runner |
| Process docs | 9 | LIFECYCLE, DEFINITION, CADENCE, ENFORCEMENT, TEST_STRATEGY, + templates |
| Framework ADRs | 3 | plugin distribution, GitHub over Linear, registry-over-enforce-all |
| Tests | 24 | `tests/hooks_test.sh`, all passing |

**Rule status:** 34 mechanically enforced · 15 tracked debt with triggers · 13 judgment · rest scaffold/agent.

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

### A4 — Interview is not resumable · ✅ built in 1.11.0, acceptance test owed

Shipped 2026-08-10: Step 0 resume-or-discard (fail-loud on corrupt state),
per-round persistence to `.claude/.init-state.json`, idempotent scaffold via
`written_files`, delete-on-success only. Shape lives in `scaffold-spec.md`
§ *Init state file*; ignored via `gitignore.tmpl`.

**Still owed — the live proof:** kill `/project-init` after Round 2, re-run, it
resumes at Round 3 without re-asking. Kill mid-scaffold, re-run, it completes
without duplicating. Needs an interactive run in a scratch repo. Until it runs,
this is implemented, not proven.

---

### A2 — Registry duplicated per project · **high** · effort M

**Why:** `/project-init` copies `REGISTRY.md` and prunes it. Framework registry and
N project registries can disagree with no detection. **This is S-05 committed by the
framework that defines S-05.**

**Build:**
1. Project holds `.claude/rules/manifest.json`: `{rules:["C-01","S-01",...], overrides:{"S-03":"TEST"}}`
2. Rule text stays in the plugin — single source
3. `scripts/render_registry.py --manifest` prints the project's registry view on demand
4. `/project-audit` validates every ID in the manifest exists in the plugin registry (covers A9)
5. `upgrade.py` gains manifest reconciliation — new plugin rules appear as `NEW`

**Done when:** a project has no `REGISTRY.md` file, `render_registry.py` produces the
same view it used to store, and an unknown ID in a manifest fails the audit.

**Files:** new `scripts/render_registry.py`, `skills/project-init/SKILL.md`,
`skills/project-audit/SKILL.md`, `scripts/upgrade.py`

---

### A10 — No measurement of which rules fire · **medium** · effort M

**Why:** hooks know exactly what they blocked; nothing records it. Pruning is
guesswork and the 400-line budget is enforced by taste. Sharper signal available: a
rule firing constantly is usually a **design** problem the guard is papering over.

**Build:**
1. Every `deny()` in `guard.sh` / `rule-zero.sh` appends
   `TAB-separated: timestamp, rule_id, path_or_cmd_prefix` to `.claude/.enforcement-log`
2. Tag each deny with its registry ID (C-01, C-05, ST-*, …) — currently they have prose reasons only
3. `session_report.py` gains a rules-by-fire-count section
4. `/retro` reads it: never-fired-in-6-months → prune candidate; fires-daily → design fix

**Done when:** `session_report.py` prints a fire-count table and `/retro` cites it.

**Files:** `hooks/guard.sh`, `hooks/rule-zero.sh`, `scripts/session_report.py`,
`skills/retro/SKILL.md`

---

### A5 — Scaffolder has no dry run · ✅ built in 1.12.0

Shipped 2026-08-10: `--plan` runs the same decision path through Step 2, prints
the full plan (files AND non-file side effects), writes nothing — state stays in
memory; persisting it for a later resume is an explicit end-of-plan offer
(1.13.1). RETROFIT defaults to `--plan` first. Live proof rides with the A4
acceptance test: a real `--plan` run must write zero files and match a real run.

---

### A13 — ST-01 fires on import-time-populated registries · **low** · effort S

**Why:** first live test (GHL-MCP, 2026-08-10) — `check_statelessness.py` flagged a
module-level `Record` whose only mutations are module-top-level registration calls
(`registerNativeTab` at import time). Static after load, identical on every
instance: a false positive. The first thing a wrongly-firing gate teaches a mature
repo is to disable it — the exact fate the gate exists to avoid.

**Build:** either (a) teach the scanner to clear collections mutated only during
module evaluation, or (b) document the `stateless-ok` protocol for the
registration pattern in `statelessness.md` and have the finding message point at
it. Red-then-green proof either way: the GHL-MCP pattern must pass, a
request-time mutation must still fail.

**Files:** `scripts/check_statelessness.py`, `templates/rules/statelessness.md`

---

### First live test — executed 2026-08-10, findings folded back

Target: `roofadvisor/GHL-MCP` on a scratch clone; deliverable is their PR #1042
(24 findings, 15 danger-annotated proposals; VERIFY green). Kit-side outcomes:
ST-01 false positive → **A13**; audit skill assumed a scaffolded repo → **absent
mode + adoption-recommendation shipped in 1.14.0**; `session_report.py`'s no-log
fallback behaved to spec; the report-document contract (dedicated branch, never
pushed unasked) held in practice. Six PR-review findings on the shipped text →
fixed in **1.13.1**. Still owed from the test: the A4/A5 kill/re-run acceptance
proof.

---

### A6 — Hook precedence unspecified · **medium** · effort S

**Why:** two `PreToolUse` hooks now match `Write` (`guard.sh`, `rule-zero.sh`).
Undefined and undocumented: execution order, what happens when one blocks and one
passes, and whether plugin hooks merge or override a project's own
`.claude/settings.json`. Will produce one confusing failure at the worst time.

**Build:**
1. Verify actual behavior empirically, then document it in `templates/process/ENFORCEMENT.md`
2. State the intended contract: **any hook exiting 2 blocks; order does not matter
   for correctness, only for which message the user sees first**
3. Document plugin-vs-project hook interaction
4. Add a test: two hooks on the same matcher, one blocks → the call is blocked

**Files:** `templates/process/ENFORCEMENT.md`, `tests/hooks_test.sh`

---

### A11 — Plugin absence silently removes all guards · **low** · effort S

**Why:** every hook path is `${CLAUDE_PLUGIN_ROOT}/...`. If the plugin is not
installed, **every guard silently disappears and the project looks fine**. Same shape
as the `jq` bug one level up: absence reads as permission.

**Build:**
1. `/project-init` writes a minimal fallback `.claude/hooks/guard-local.sh` into the
   repo (secrets + force-push only) so key-safety survives plugin absence
2. `/project-audit` asserts the plugin is installed and at the expected version

**Files:** `skills/project-init/SKILL.md`, `skills/project-audit/SKILL.md`,
new `templates/scaffold/guard-local.sh`

---

### A9 — Rule IDs have no permanence guarantee · **low now, high later** · effort S

**Why:** if `S-05` is split or renamed, every project registry referencing it breaks
silently — nothing validates that a referenced ID exists.

**Build:** state in `REGISTRY.md` that IDs are permanent once issued; superseding
uses a new ID plus a `Superseded by` row. Add ID-validity check (folds into A2 step 4).

**Do before v2.0.**

---

## 3 — Registry debt (PROSE that should be mechanized)

From `templates/rules/REGISTRY.md`. Each already carries a promote-when trigger.
Use `/promote-rule <ID>`.

**Global — do these regardless of project:**

| ID | Rule | Target | Effort |
|---|---|---|---|
| C-06 | Conventional commits | LINT (commitlint in CI) | S |
| C-08 | Never delete a test to pass a build | TEST (test-count-decrease check) | S |
| S-03 | `catch → []` trap | LINT (ban empty-collection catch) | M |
| S-04 | New value must fail a check, not default | TEST (exhaustiveness at enum boundaries) | M |
| S-07 | Pure function must not fetch | LINT (no IO import in `pure/`) | S |
| D-06 | No raw SQL in handlers | GATE (grep) | S |
| O-05 | Never log payloads/PII/credentials | GATE (secret-scan + grep) | M |
| G-05 | Fixture edit must not delete a case | TEST (fold into `check_fixtures.py`) | M |

**Project-conditional — turn on with the module at `/project-init`:**

M-02/03/04 (money) · T-01..04 (determinism) · P-02/03/04 (capability parity) ·
ST-10..12 (statelessness) · I-06 (idempotent ingestion)

---

## 4 — Opportunities (not defects)

| ID | Item | Value |
|---|---|---|
| O4 | Conformance suite: scaffold a throwaway project per module combo, assert verify passes on the empty scaffold | **The scaffolder is the least-tested component in a system whose premise is testing** |
| O5 | Extract the doctrine (`silent-degradation`, `guards`, `capability-parity`) as a portable artifact | Most valuable content, least tool-coupled; survives a move off Claude Code |
| O6 | Cross-project rule analytics | Fires everywhere → always-on. Never anywhere → delete. One repo only → local problem |
| O2b | `/project-audit` asks the *unanswered* interview questions on an existing repo | Turns retrofit into a partial interview (A4 built — unblocked) |

---

## 5 — Notion / integration follow-ups

| ID | Item |
|---|---|
| N-01 | Migrate sync to Notion Workers when syncs/webhooks leave beta, **or at the third repo** — whichever first. Full analysis in `templates/notion/SYNC_ARCHITECTURE.md`. Four invariants make it a swap not a rewrite. |
| N-02 | `hub+local` reconciliation is documented (`/notion-sync` Mode 5) but never exercised — no project uses the mode yet |
| N-03 | Work DB `Repo` select options must be added as each repo is wired; sync fails on an unknown option |

---

## 6 — Priority order

```
NOW      B-01 Notion approval    (blocked on Ian)
         B-02 Brand Torus path   (blocked on Ian)

NEXT     A2   registry as manifest         ← start here on code
         A4   live acceptance test (kill/re-run in a scratch repo)
         C-06 commitlint  ·  D-06 raw-SQL gate  ·  S-07 pure-fn lint   (all S, do together)

SOON     A10  enforcement telemetry
         A13  ST-01 import-time-registry false positive (from live test)
         A6   hook precedence
         A11  plugin-absence fallback
         O4   conformance suite

LATER    S-03, S-04, O-05, G-05, C-08   (registry debt, M each)
         A9   ID permanence — before v2.0
         N-01 Workers migration — at 3rd repo or beta exit
```

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
