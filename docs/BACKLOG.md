# BACKLOG — f4d-kit

**Last updated:** 2026-08-11 · **Version shipped:** 1.19.0 · **Status:** all validation green (24/24 hooks, self-scans clean, all workflows parse)

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
| Rules modules | 22 | incl. REGISTRY.md with 75 rules |
| Hooks | 7 | guard, rule-zero, session-context, done-check, verify-record, format, _parse |
| Gate scripts | 10 | fixtures, contract-pin, guess-lists, rollback, statelessness, upgrade, render-registry, commits, raw-sql, pure-imports |
| Agents | 4 | schema-reviewer, integration-auditor, contract-drift-checker, verify-runner |
| Process docs | 9 | LIFECYCLE, DEFINITION, CADENCE, ENFORCEMENT, TEST_STRATEGY, + templates |
| Framework ADRs | 3 | plugin distribution, GitHub over Linear, registry-over-enforce-all |
| Tests | 54 | `tests/hooks_test.sh` (24) + `render_registry_test.sh` (11) + `gate_trio_test.sh` (19), all passing |

**Rule status:** 40 mechanically enforced · 12 tracked debt with triggers · 13 judgment · rest scaffold/agent.

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

### A9 — Rule IDs have no permanence guarantee · ✅ closed with A2 in 1.15.0

`REGISTRY.md` § *Reading this file* now states permanence (supersede with a new
ID, never renumber); `render_registry.py --validate` and `upgrade.py` fail on
any reference to an ID that does not exist.

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
| O4 | Conformance suite: scaffold a throwaway project per module combo, assert verify passes on the empty scaffold — **now also owns**: full-spec plan/execute parity (the A4/A5 acceptance proved parity over a 19-file subset; workflows, issue templates, guard tests, and the framework-state baseline were not exercised) and full-Step-4 delete-on-success discipline | **The scaffolder is the least-tested component in a system whose premise is testing** |
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

NEXT     A11  plugin-absence fallback   ← start here

SOON              O4   conformance suite (now also owns: full-spec plan/execute parity + full-Step-4 delete discipline)

LATER    S-03, S-04, O-05, G-05, C-08   (registry debt, M each)
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
