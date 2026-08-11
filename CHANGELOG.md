# Changelog

## 1.14.1 — the load-path doctrine was wrong, and it taught a live audit a false finding
The kit asserted in seven places that a session started in a subdirectory "never loads the repo-root instruction files." Live evidence disproved it: `CLAUDE.md` auto-loads with an **upward walk** from the session's cwd — a root file reaches `dist/reporting` fine (verified directly, and the audited repo's own phase-0 plan had verified the same independently, labelled "diagnosed wrong once already"). The GHL-MCP audit repeated the kit's claim verbatim as finding M2 and had to retract it under PR review.

What was, and remains, true: `AGENTS.md`-style guides and the `.claude/rules/*.md` modules never auto-load — without `session-context.sh` every session runs on `CLAUDE.md` alone. All seven sites now state that; `session_report.py`'s subdirectory FINDING is downgraded to a relative-path NOTE (doubly wrong before: sessions in its log had, by construction, run the hook that wrote the log). The hook itself is unchanged and still ships.

Also from the same review round: **no in-progress markers may survive into a committed audit report** — the live audit shipped a "recorded once the run completes" placeholder alongside the completed result.

## 1.14.0 — what the first live test taught the audit
`/project-audit` ran for the first time against a real, unscaffolded repo (GHL-MCP, on a scratch clone → their PR #1042) and two structural gaps surfaced.

**FRAMEWORK-absent mode.** The skill assumed a scaffolded repo; on an inherited or unscaffolded one the auditor had to improvise which checks translate. Now specified: which checks run as-is (enforcement layer judged against the repo's own instruction files, verify integrity, rules-vs-reality, spot checks), which are skipped **by construction** and must be declared in *Not checked* (version/drift, kit-registry honesty, kit gate scripts), and org checks recommend `/org-profile` when no profile exists.

**Adoption recommendation** is now a required report section when FRAMEWORK is absent or partial: the specific slice to adopt first, what NOT to adopt because a mature local equivalent exists, and the next step (`--plan`). Advice with dangers attached — merging the report adopts nothing.

**Backlog:** A13 opened for the ST-01 import-time-registry false positive found live; the test record and its foldbacks are in the backlog.

## 1.13.1 — review fixes from the first live test's PRs
Six review findings on #2/#3/#4, all confirmed against the shipped text:

- **Resume could not tell "pre-existing" from "interrupted mid-write"** — in RETROFIT both are absent from `written_files`, and the rules said both "rewrite it" and "never touch it". The state file now captures a `preexisting` inventory at plan confirmation; unrecorded planned targets redo their retrofit-safe (idempotent) operation when pre-existing, rewrite outright when not.
- **The scaffold commit was not resumable** — interrupt after the commit, resume, and `git commit` fails on `nothing to commit`, blocking verification and cleanup. Non-file steps now record into a `phases` map; the commit must be recorded, idempotent side effects may re-run.
- **Plan mode wrote the state file it claimed not to write** — a `--plan` on a RETROFIT repo left an untracked file in the target, contradicting "writes nothing". Plan mode now keeps state in memory and *offers* persistence at the end; only an explicit yes writes.
- **The plan omitted non-file side effects** — the commit, the upgrade baseline, the **remote** `SINGLE_INSTANCE` variable, and Step 4's stack/migrations/seed never appeared in the "complete" plan. They are now required plan output; P-04 parity covers effects, not just files.
- **"Read-only" contradicted the mandated report write** — the audit header now states its single exemption explicitly.
- **`file:line` was required where no line can exist** — absence and external-state findings may now cite a listing, command output, or external-system state; never omit a finding for lack of a line, never invent one.

## 1.13.0 — audit writes its report as a document
`/project-audit` now writes `docs/f4d-audit-<date>.md` into the audited repo (dedicated branch, never pushed unasked) — header, three-sentence summary, findings with file:line evidence, proposed changes ranked by what bites soonest with an explicit **danger** column (what adopting each change could break in this repo — a hook blocking a current workflow, a gate going red on existing code), a prioritized todo list handable to a fresh session, and a **Not checked** section, because silence reads as "checked and fine". The document is the only file the audit writes; the terminal summary stays. Requested for the first live retrofit test: audit a scratch clone, review the document, decide separately.

## 1.12.0 — A5: scaffolder dry run
`/project-init --plan` runs the identical interview and decision path, prints the complete plan — file tree, modules with the answer that decided each, gates/hooks/agents, local-stack choice, verify command — and stops without writing. P-04 applied to the scaffolder itself: the registry demanded preview/execute parity of every project while the scaffolder had no preview at all. Plan mode persists interview state, so a later real run resumes from the confirmed plan without re-asking (composes with 1.11.0). RETROFIT repos get `--plan` first by default.

## 1.11.0 — A4: resumable interview
`/project-init` was the longest single operation in the system — four interview rounds and ~30 file writes — with no persistence: an interruption lost everything and left a half-written directory.

Now: answers persist to `.claude/.init-state.json` after every completed round, the confirmed plan is recorded at Step 2 approval, and every scaffold write appends to `written_files`. A new Step 0 detects existing state and offers resume-or-discard — with a fail-loud path for a corrupt state file (never guess at partial state). The scaffold is idempotent on resume: skip exactly what `written_files` records; on-disk-but-unrecorded means interrupted mid-write, so rewrite. In RETROFIT, the resume list governs only files the run wrote — the never-overwrite rules still own everything pre-existing. Success (Step 4 verification passing) is the only thing that deletes the state; interrupted and failed runs both keep it. The state file is gitignored via `gitignore.tmpl`; its shape lives in one place, `scaffold-spec.md` § *Init state file*.

**Acceptance test still owed:** the kill-after-Round-2 / kill-mid-scaffold live re-run proof needs an interactive `/project-init` in a scratch repo. Until that runs, this is implemented-to-spec, not proven — same standard as any other guard.

## 1.10.2
- B-03 closed: the kit is published as `f4d/f4d-dev-env-configurator` (private). START_HERE, README install section, and the backlog now reference the real remote instead of instructing a push to a repo name that never existed. The plugin/product name remains `f4d-kit`; only repo-slug references changed.

## 1.10.1
- Added `docs/BACKLOG.md` — every open finding, blocked item, registry debt entry, opportunity, and working agreement in resumable form. Each item carries why it matters, what to build, done-when criteria, and files touched, so work can be picked up cold without re-deriving the reasoning.

## 1.10.0 — architecture pass
Full architecture review in `docs/ARCHITECTURE_REVIEW.md`. Verdict: the enforcement architecture is sound; the lifecycle architecture was built for day one and under-built for day two hundred. Twelve findings, top three fixed here.

**Framework violated its own G-02.** Five of seven hooks had no test, including `session-context.sh` — the load-path fix, the most load-bearing hook in the system. Now 24 test cases covering all seven. Writing those tests found a real bug: `done-check.sh` used `git diff HEAD`, which returns nothing in a repo with no commits and **misses untracked files entirely** — a brand new source file did not count as a change. Now uses `git status --porcelain`.

**A1 — upgrade path (critical).** `scripts/upgrade.py` + `/framework-upgrade`. Diffs a project's `.claude/` against the plugin and classifies each file as UNCHANGED / FRAMEWORK / LOCAL / CONFLICT / NEW / ORPHAN against a recorded baseline. Applies FRAMEWORK only; local customizations survive; conflicts go to a human. All four classifications proved with a live test. Without this, N repos scaffolded over N months sit at N versions and *"we are always working on the same system"* quietly becomes false.

**A3 — the framework had no ADRs of its own.** Three recorded: plugin distribution, GitHub over Linear, and document-everything-track-enforcement. Each with the alternatives that lost and why.

**A12 — secret preflight.** `preflight.yml` asserts that `CLAUDE_CODE_OAUTH_TOKEN`, `NOTION_TOKEN`, and `NOTION_WORK_DB` exist when the workflows depending on them are present. The framework told you what to add and never checked that you did.

**A7 / A8 — gate cost and false firing.** The five script gates collapse into one job: one checkout, one Python setup, all five checks with grouped output. `STATELESS_SINGLE_INSTANCE` now comes from a repo variable the scaffolder sets from the interview answer, so the statelessness gate does not fire wrongly on a single-instance project.

Remaining findings A2, A4, A5, A6, A9, A10, A11 are documented with severity, effort, and priority in the review.

## 1.9.0 — statelessness
A failure class the framework had no coverage for: state that works on one instance and fails intermittently on two. Structurally invisible, because local dev, tests, and CI are all single-instance — the first multi-instance environment is production.

**Interview** — Round 1 gains *"Will this ever run more than one instance?"* (`yes` / `no` / `serverless`; autoscale and serverless are both yes). A `yes` includes the module, switches the local stack to two instances, and ships the cross-instance tests — not asked about separately, that is what yes means. A `no` gets ADR 002 recording the choice and its reversal cost. Round 3 adds two follow-ups: what survives between requests (walk the list, don't accept "nothing"), and where long-running progress lives if the instance dies.

**`templates/rules/statelessness.md`** — the contract (any instance serves any request; any instance may die between requests), a where-state-must-live table covering sessions, caches, rate limits, locks, uploads, temp files, jobs, schedules, progress, and websockets, and the rules that follow.

**`scripts/check_statelessness.py`** — gate for ST-01..ST-07: module-level mutable collections, in-process locks, in-process schedulers, local-disk writes, migrations at boot, in-memory sessions, in-process rate limiters. Line-level `stateless-ok` annotation for genuine exceptions. Proved red on five planted violations, green when clean, and fixed so it no longer matches its own pattern table.

**`templates/scaffold/docker-compose.multi.yml.tmpl`** — the environment fix, and the most important part of this release. Two app instances behind nginx round-robin, redis for shared state, and migrations as a **separate** service so instances never race at boot. Now the default local stack for any multi-instance project; single-instance requires a recorded decision.

**`templates/tests/statelessness_test.py`** — cross-instance write-then-read, session survives an instance switch, rate limit is shared across instances, idempotent write through the load balancer, and a restart-loses-nothing test.

**Registry** — 14 new ST-* rules. Seven are gated, one is scaffold-enforced, one is tested; the rest carry project-conditional promote-when triggers.

**Also** — Definition of Done gained a Statelessness section, `/project-audit` checks whether the local stack is single-instance (if it is, every ST-* bug in that repo is currently invisible), and the org profile gained `multi_instance` and `shared_store` defaults.

## 1.8.0 — document everything, enforce what's ready, track the rest
Answers "can't we just document them now and figure out enforcement later?" — yes, provided the gap is tracked rather than forgotten.

**`templates/rules/REGISTRY.md`** — every rule the framework holds, with an ID (C-, G-, S-, P-, D-, I-, K-, M-, T-, O-), the layer it should live in, what enforces it today, and a promote-when trigger for anything still prose. `PROSE` on a mechanisable rule is now a tracked debt with a ticket, not an invisible gap. `JUDGMENT` is a finished state — do not mechanize it.

**Holes closed**
- H2 *agents were advisory* → `templates/github/gates.yml`: six CI jobs that FAIL the build, each named with the rule IDs it enforces. The schema job makes the agent's verdict a gate by acting on its PASS/FAIL line.
- H3 *rollback never tested* → `scripts/check_rollback.py`: every migration needs a down-path or an explicit irreversible declaration, and "revert the commit" is rejected as a rollback when a migration ran.
- H4 *contract drift not version-enforced* → `scripts/check_contract_pin.py`: fails when a consumer is unpinned or more than one major behind.
- H5 *fixtures rot silently* → `scripts/check_fixtures.py`: requires `_meta.recorded_at`, fails at 90 days, and requires all four fixtures per adapter.
- H6 *hub+local had no reconciliation* → `/notion-sync` Mode 5: three-way divergence report, hub canonical for mirror fields, and a 5%-for-two-checks trigger to drop the mode.
- H7 *promotion path was manual* → `/promote-rule`: identify by ID, confirm the rule was actually in context, choose the layer, build it red-first, wire it, update the registry, and promote to the framework only after it has proved itself in one repo. Also owns demotion.
- S-05 *guess lists* → `scripts/check_guess_lists.py`. It immediately caught real duplication in this kit's own scripts; fixed by extracting `scripts/_common.py`.

**Reference tests** — `templates/tests/guard_tests.{py,ts}` implement S-01 (non-empty before assertion) and S-02 (no raw ids in output) in both languages, each with a case proving the guard fails. Copied into every project by `/project-init`.

**Audit** — `/project-audit` now verifies **registry honesty**: every row claiming HOOK/TEST/GATE must have that check actually wired and running. A registry asserting enforcement that does not exist is worse than no registry.

## 1.7.0 — evidence, not recollection
- **Session telemetry.** `session-context.sh` now appends to `.claude/.session-log`: timestamp, whether the session started at the repo root, which subdirectory, whether CLAUDE.md existed, and the rules count. `verify-record.sh` (PostToolUse:Bash) records verify runs.
- **`scripts/session_report.py`** turns that log into findings with counts — how many sessions loaded no rules, how often verify ran, whether the rules set changed mid-window. This replaces "observe for a week and then decide," which no agent can do because every session starts blank.
- `/project-audit` and `/retro` now run the report **before** forming any opinion, and say so explicitly when there is no log rather than waiting for one.
- **`templates/process/TEST_STRATEGY.md`** — the pyramid mapped to this framework's real failure classes, per-component coverage, the seven guard tests ranked by yield, non-percentage coverage targets, and the four anti-patterns already hit in this kit.
- `.session-log` and `.last-verify` gitignored — local telemetry, not shared state.

## 1.6.0 — enforcement pass
Driven by a field report: a full set of rules was in force and none of them fired, because they were prose.

**Fixed a defect in this kit's own guards.** `guard.sh` depended on `jq`. On any machine without it the parse returned empty and the hook **exited 0 silently** — a key-safety guard that looked installed and enforced nothing. Both hooks now fall back to python3, then sed, and **fail loud (exit 2) rather than allowing** when input cannot be parsed.

**New hooks**
- `session-context.sh` (SessionStart) — fixes the load-path defect. `CLAUDE.md` only auto-loads from the directory a session starts in; a session started in `dist/` or `packages/x/` never saw the repo-root rules at all. This walks to the repo root and injects them regardless of cwd.
- `rule-zero.sh` (PreToolUse:Write) — blocks creating a variant alongside an existing canonical file (`reportV2`, `report-final`, `new-report`) until the existing one is named. Mechanical fix for the twenty-near-duplicates pattern.
- `done-check.sh` (Stop) — refuses a silent "done" when source changed and verify never ran, or ran before the newest change.

**New rules modules** — `guards` and `silent-degradation` are now always included, never asked about
- `silent-degradation` — no degrade-to-default, the `catch → []` trap that passes every downstream "is anything missing" gate, empty-collection vacuous pass, guess lists, one canonical resolver, the hardcode boundary, never render a raw id, cross-check load-bearing numbers
- `guards` — red-then-green hygiene, where a rule belongs by layer, naming the unguardable residual
- `capability-parity` — consumer enumeration on contract change, UI-as-proof, row-level vs call-level failure, preview/execute parity

**New process doc** — `templates/process/ENFORCEMENT.md`: the three-layer model, the load-path defect, and an honest audit of which f4d-kit rules are still prose that should not be, in priority order

**Other**
- Definition of Done gained Guard hygiene and Contract changes sections
- `/retro` now asks "was it even in context?" before "was it ignored?"
- `/project-audit` checks the enforcement layer first, and greps for the silent-degradation patterns
- `verify.yml` gained path filters so docs-only changes skip the full gate
- Added `tests/hooks_test.sh` — 14 red-then-green cases, all passing

## 1.5.0
- **Hub segmentation.** Work DB gained `Company` and `Hub Mode` properties plus By-company and per-company views. One hub database serves every company; adding a company is an option plus a view, not a new database
- Added the hub-mode branch to both interviews: `hub` (default) | `hub+local` | `local`, with the cost of each stated. Recorded in the org profile so it is asked once per company
- Added `templates/notion/SYNC_ARCHITECTURE.md` — documents the GitHub Actions path (shipped), the Notion Workers path (beta target, declarative schema and hosted runtime), and External Agents (alpha), with explicit migration triggers and the four invariants that make migration a swap rather than a rewrite
- `/notion-sync` now points at the architecture doc before any sync change

## 1.4.0
- Added `/repo-builder` — the front door. Orchestrates `/org-profile` → `/project-init` → `/notion-sync` → `gh repo create` → first commit → push → verify, in one pass
- Narrowed `claude-code-review.yml` to high-risk paths only: migrations, models, api/routes/handlers, webhooks, adapters, auth, billing, crypto/hashing, `*.sol`, openapi, schemas, workflows, Dockerfiles. Everything else is covered by verify plus human review
- Review prompt is now a ranked checklist rather than an open request, and explicitly excludes style

## 1.3.0
- Added `/notion-sync` — Notion Work DB as the triage UX and work queue over GitHub Issues
- `templates/notion/WORK_DB_SCHEMA.md` — schema with explicit field ownership (GitHub mirror vs triage vs context) and seven views including a Stale view for sync health
- `scripts/notion_sync.py` — one-directional GitHub → Notion sync; writes only the fields it owns, preserves all triage fields
- `templates/github/` — `notion-sync.yml`, `claude.yml` (issue → PR), `claude-code-review.yml` (auto review), plus `bug.yml` and `feature.yml` issue forms
- `/work-intake` now triages in the Work DB; `/ship-it` writes spec, ADR, and notes back
- `/project-init` wires the workflows and issue templates when the org profile has the GitHub App and a Work DB
- Org profile gained `notion_work_db`

## 1.2.0
- Added `/org-profile` — company-level context captured once per company, inherited by every project in it
- Added `templates/org/ORG.template.yml` — profile schema: identity, GitHub org, conventions, stack defaults, automation, business context, constraints
- `/project-init` gained **Round 0**: which company, project identity, silo-vs-shared, audience, expected lifespan. Runs `/org-profile` automatically when no profile exists, and skips every question a profile already answers
- Scaffold now writes `.claude/rules/org.md` from the company's constraints block
- CLAUDE.md template carries an org/audience/lifespan header
- `/project-audit` checks org alignment: profile exists, constraints in sync, conventions match, board membership

## 1.1.0
- Added the product management layer: `/work-intake`, `/write-spec`, `/decision-record`, `/ship-it`, `/retro`
- Added `templates/process/`: LIFECYCLE, DEFINITION (Ready + Done), CADENCE, and spec/ADR/PR templates
- `/project-init` now scaffolds `docs/specs/`, `docs/decisions/`, `docs/log.md`, `docs/intake.md`, the PR template, and ADR 001 for the chosen stack
- CLAUDE.md template gained a Process section pointing at the lifecycle
- Generalized webhook signature header convention — no project-specific naming

## 1.0.0
- Initial framework: `/project-init` interview skill, 17 rules modules, guard/format hooks, 4 subagents, scaffold templates, `/project-audit`, `/new-module`, `/new-integration`, `/contract-first`
