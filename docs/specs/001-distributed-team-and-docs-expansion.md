# 001 — Distributed-team discipline, instruction/doc coherence, and the domain/ownership expansion

- **Status:** Draft
- **Date:** 2026-08-17
- **Size:** L (six capabilities — built one per branch, not as one change; see Phasing)

## Problem

f4d-kit governs correctness *inside* one change made by one person. It has no
rules for the seams between people, repos, and tools: two people picking up the
same backlog item; a branch that quietly grows a second concern; work sitting
unpushed for a day; four related repos drifting into four different rulebooks and
four different AI-tool instruction files; and planning documents landing in three
different directories depending on which tool wrote them. Three classes of
knowledge the team relies on have no home in the kit: **domain rules** (business
logic that must hold), **accuracy-critical paths** where no automated check can
prove correctness and a human must sign off, and **standing documentation**
(product docs, end-user how-tos, operations runbooks, session handoff notes).

## Why now

RoofAdvisor is going from one repo (GHL-MCP) to 3–4 related repos worked by a
distributed team plus several AI coding tools (Claude, Cursor, Codex, Gemini).
Once there is a second repo, a second person, and a second tool, these ungoverned
seams become the dominant source of waste — duplicated work, divergent
conventions, silent accuracy regressions, and design docs stranded in gitignored
scratch dirs. Observed live in GHL-MCP today: planning docs loose in `docs/`
(`production-plan.md`, `highlevel-action-implementation-plan.md`, …), superpowers
artifacts in `.superpowers/sdd/<slug>/` and `.superpowers/brainstorm/`, and the
kit's own `docs/specs/` convention — three conventions, zero reconciliation.

## Interaction model — one interview, agent-prepped, human-approved

**This is the load-bearing decision.** Nothing here is a series of slash commands
the user must memorize. Every capability — new repo or retrofit — is surfaced
through a single **interactive interview**, and the agent does the analysis
*before* the human is asked anything.

- **New repo:** `/project-init` runs the interview rounds (below); the human
  answers questions, the agent scaffolds.
- **Retrofit / audit:** `/project-audit` does the *discovery* first — finds rules
  scattered outside managed blocks, planning docs in non-canonical directories,
  undeclared companions, missing gates, MANUAL-eligible paths — and **prepares a
  list of proposed adoptions**. Then one approval pass presents each candidate in
  plain language: *"You have implementation plans loose in `docs/`; adopt the
  canonical `docs/plans/` home and move them? [y/n]"*, *"`AGENTS.md` states 3
  rules not in any module; adopt them into `collaboration.md`? [y/n]"*, *"Declare
  superpowers and install it now? [y/n]"*. The human approves or declines each;
  **nothing is applied without that yes**. Adoption is the human's decision, the
  same reconcile posture as `upgrade.py` — the agent never silently reorganizes
  prose or moves files.

The rule: the agent workflows the process up to the decision point; the human
only ever approves final inclusion.

## Safe partial adoption — do no harm (governing principle)

These repos are live and in production. The kit must be safe to adopt one slice
at a time, across many repos, without its own machinery breaking the host. Four
invariants, above all six capabilities:

1. **Un-opted-in repos are inert.** Every plugin-declared hook calls
   `hook_opted_in()` first and exits 0 unless the repo carries
   `.claude/.framework-state.json`. Installing the kit enforces nothing in a repo
   that has not opted in — the many RoofAdvisor repos we have not touched are
   unaffected.
2. **Never wire a gate for a rule the repo does not hold.** A gate that fires on
   an absent rule is a confusing red build — harm. Only the jobs whose rules the
   repo actually holds are written; the rest are deleted, and a check verifies it.
3. **Never move or rename without repointing consumers.** Any relocation
   inventories code + test + link consumers and repoints them in the same step
   (the AR-AP lesson); a bare redirect stub is not an acceptable outcome.
4. **Every proposed change carries a pre-flight harm check.** Before the audit
   proposes a change it answers: would this go red on the current baseline, break
   a consumer, or make a hook block a live workflow? If yes, it is flagged and
   never auto-applied. Each adoption slice is independently safe and reversible;
   "partially adopted" is a first-class, reported state, never a broken one.

**Adoption must be reversible.** Every capability the interview can turn *on*
must be turn-off-able by a consumer-aware **adopt-out** — the symmetric inverse
of `/project-init`. Removing an adopted thing (the A11 guard floor, an
instruction-sync managed block, a gate in CI) is not freehand `rm`: it unwires
or removes atomically, checks for consumers first (a test that spawns the guard,
code that reads a rendered file) exactly as the canonical doc-layout promote step
inventories executable/test consumers before a move, **defaults to disable over
delete when a consumer exists** (disable ≠ delete — un-wiring a hook leaves its
test green; deleting the file turns it red), and records the removal. The things
we adopt are additive, but some are security controls — the A11 guard-local floor fails loud on unparseable input and blocks secret writes and force-pushes, so unwiring it REDUCES enforcement. The adopt-out classifies each removal's enforcement impact, surfaces a security-reducing removal explicitly at approval, and records what protection was dropped; the requirement
is that backing a capability out is a first-class, audited operation, not manual
surgery. Tracked as A26. (Live trigger: GHL-MCP's 2026-08-17 body-scan guard
hardening self-blocked every edit to the guard because it grew no exemption for
its own source/test; the fix was a target-scoped self-exemption, and the question
it raised — "can we back this out safely?" — is what this requirement answers.)

## Success looks like

Each is verifiable by someone outside this work.

- `/project-init` (new) and `/project-audit` (retrofit) turn each capability on or
  off per repo through the interactive interview above — never by copying a
  divergent rulebook in, never requiring memorized commands.
- One rule source renders `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.cursor/rules/*`
  deterministically; drift between them fails CI.
- Every planning artifact has exactly one canonical directory; a doc outside its
  home is a named finding, and superpowers' `.superpowers/sdd` / `brainstorm`
  outputs are promoted into it, not stranded.
- A PR whose author is not the linked issue's assignee fails a gate — on
  multi-contributor repos only.
- A PR touching a MANUAL-tier path fails unless it carries a signed human attestation.
- A rule proven in one repo can be promoted back into the plugin and propagated to
  the others (`/retro` → `/promote-rule` → `/framework-upgrade`).

## Scope

**Doing** — six capabilities, each a module/feature added one branch at a time:

1. **Collaboration** (`collaboration.md`, CB-01…CB-05 + `check_assignee.py`) —
   CB-01 assign-before-branch, CB-02 one-concern-per-branch, CB-03 a PR links
   exactly one item (checkable), CB-04 the diff matches that item (JUDGMENT),
   CB-05 push-on-cadence. Force-push is **not** a new CB rule — it stays **C-02**
   in `core.md`, cross-referenced here, never duplicated (a second row would let
   the two acquire conflicting enforcement status). Always-on for multi-person
   repos only.
2. **Instruction-file sync** (`render_instructions.py` + `check_instruction_honesty.py`)
   — rule-module frontmatter is the single source; render to CLAUDE/AGENTS/GEMINI/Cursor
   in delimited managed blocks; `--check` fails on drift. Backbone the rest ride on.
3. **Documentation + canonical doc-layout** (`documentation.md` + templates +
   `check_docs_layout.py`) — product docs, end-user how-tos, operations runbooks,
   handoff/session notes, AND the artifact-ladder layout map + enforce/promote
   (below), AND a **doc-follows-behavior** rule — a PR that changes user-visible behavior must touch the relevant user/operator docs, with a gate that flags a behavior-changing diff leaving them untouched (from GHL-MCP PR #1133: a `/imports` chip-count change updated impl + tests but not `operator-documentation.json`). Opt-in by lifespan/production status.
4. **Domain rulebook + MANUAL tier** (`domain.md` + a new registry tier +
   `check_attestation.py`) — each repo declares accuracy-critical / known-vuln
   paths; a MANUAL rule requires a signed human attestation in the PR when such a
   path changes. **Needs an ADR** (adding a registry tier is hard to reverse).
5. **Ownership registry** (kit-native `ownership` source → generated `CODEOWNERS`
   + audit check) — kit-native and offline-validatable; GitHub CODEOWNERS is a
   rendered output, not the source of truth.
6. **Artifact ladder** (lifecycle + templates) — the full planning ladder with a
   template and an entry/exit handoff rule per rung (below).

**Not doing**
- No new *always-on* rules beyond collaboration (multi-person) + instruction-sync;
  capabilities 3–6 are opt-in per interview, never inherited by default.
- No Cowork adapter for these (O7, separate track); hooks/gates here are
  Claude-Code / CI mechanisms.
- No silent auto-apply in retrofit — audit reports, human approves, then apply.
- No silent auto-install of any companion; installs are *offered on declaration* only.
- CB-04 (diff-matches-the-linked-item) stays JUDGMENT; mechanizing it yields false positives. CB-03 (a PR links exactly one item) is the separate, checkable half and stays LINT — distinct IDs, so neither is left ambiguous. Force-push stays C-02 (`core.md`), never a collaboration duplicate.

## The artifact ladder (capability 6, detailed)

One canonical home per rung, one template per rung, one handoff rule per gap.

| Rung | Canonical home | Handoff rule (entry to next) |
|---|---|---|
| Research / brainstorm | `docs/research/` | A spec cites the research that motivated it |
| Design / spec | `docs/specs/NNN-*.md` | No Building without a linked spec (M/L) |
| Implementation plan | `docs/plans/NNN-*.md` | No Building without a plan that matches the spec's scope |
| Todo (in-flight) | the issue / PR checklist | one linked item per PR (CB-03) |
| Backlog | `docs/BACKLOG.md` | scope found mid-branch becomes a backlog item, not a bigger branch (CB-02) |
| Decision | `docs/decisions/NNN-*.md` | a hard-to-reverse choice gets an ADR before it ships |
| Launch | `docs/launch/NNN-*.md` | `ship-it` gates on a launch list |

**Enforce + promote (`check_docs_layout.py`):** a planning doc outside its
canonical home fails the gate and names where it belongs; a `.superpowers/sdd/` or
`.superpowers/brainstorm/` artifact is flagged for **promotion** into the
canonical home (superpowers stays the *authoring* tool; the kit *files* the
durable artifact so the whole team and every AI tool find it in one place). The
`.superpowers/sdd/.gitignore` means those artifacts may never be committed — the
promote step is what makes the design doc durable and shared. Relocation is never just a file move: scripts and tests routinely hard-code doc paths — observed live in AR-AP PR #84, where `scripts/cross_phase_quality_gates.py` and `tests/test_phase6_governance_docs.py` read files under `docs/superpowers/plans/`. `check_docs_layout.py` therefore inventories the **executable and test consumers** of any path it proposes to move, and the promote step repoints them; a redirect stub alone leaves a content-based test reading a five-line stub and failing. Repoint code and tests, not only cross-doc links. The enforcement is a tree-wide **doc-link-resolution gate**: every repo-relative `docs/…` reference in every tracked file must resolve, with a reasoned **bidirectional `ALLOWED_MISSING` allowlist** (an entry that starts resolving is itself a failure, so the list cannot rot). This is modeled directly on AR-AP's `tests/test_doc_links.py`, already proven in production — it is what turns invariant #3 (never move without repointing) from a hope into a gate.

## Learning flow back (repo → plugin)

Coherence is bidirectional. Repos render the shared rulebook *down*; proven local
rules push *up*:

1. `/retro` (monthly or after an incident) surfaces a local rule or convention
   that has earned its keep in a repo.
2. `/promote-rule` lifts it into `templates/rules/` (or the registry), bumps the
   plugin version, and records the promotion — with the same registry-honesty
   check (a promoted HOOK/TEST/GATE row must point at a real check).
3. `/framework-upgrade` propagates the bumped version to the other repos, where
   `upgrade.py` reconciles it as a *candidate* (adoption stays a per-repo human
   decision, never a forced sync).
4. `check_instruction_honesty.py` keeps the rendered instruction files in step in
   between.

A local rule is only promoted after it has proven itself in at least one repo —
never speculatively.

## Data

- **New rules modules:** `collaboration`, `documentation`, `domain`, `ownership`
  (22 → 26); frontmatter (`id`, `always_apply`) added to *every* existing module.
- **New registry sections:** Collaboration, Documentation, Domain, Ownership.
- **New status-vocabulary row:** `MANUAL` — "a human must attest; no automated
  check can prove it. Enforced by presence of a signed attestation, not by
  re-checking the claim." Distinct from JUDGMENT (not enforced) and from an ADR
  (records a choice, not a verification).
- **New scripts:** `render_instructions.py`, `check_instruction_honesty.py`,
  `check_assignee.py`, `check_attestation.py`, `check_docs_layout.py`, `check_doc_links.py` (**promoted from AR-AP's `test_doc_links.py`**), and `gen_codeowners.py` (13 → ~19 gate/helper scripts).
- **Canonical source of truth unchanged (A2):** rule text lives in the plugin;
  rendered instruction files, CODEOWNERS, and filed docs are *derived*.

## External systems

| System | Direction | Metered | Failure mode if unavailable |
|---|---|---|---|
| GitHub API (issue assignees) | read | no | `check_assignee.py` fails loud (G-03) unless `no-assignee-check` label; never passes blind |
| GitHub CODEOWNERS / branch protection | config (rendered) | no | review requirement not enforced; audit reports it; kit-native `ownership` still validates offline |

## Small-team helper — create-branch-and-assign

For small teams, offer a one-step flow that **creates the branch and assigns the
linked issue to the author at the same moment** (a `/claim <issue>` micro-action
or a `work-intake` option), so "assign before branch" is one action, not two. The
`check_assignee.py` gate stays, but the friction it guards against is removed at
the source. Solo repos: the gate is disabled entirely (a `SINGLE_CONTRIBUTOR`
repo variable, mirroring `SINGLE_INSTANCE`).

## Companion install — offered on declaration

When the interview declares a companion (e.g. superpowers), offer to install it
then and there: `claude plugin marketplace add` + `claude plugin install`, only
after an explicit yes. Never a silent auto-heal — a consented, declared install,
so `check_companions.py`'s G-06 promise is backed by an actual install rather than
a dangling declaration.

## Failure modes

- **Instruction files drift from the registry** → `check_instruction_honesty.py` fails; the drifted block is named.
- **Planning doc in the wrong directory** → `check_docs_layout.py` fails and names the canonical home; `.superpowers/` artifacts flagged to promote.
- **Assignee gate can't reach the API** → fails loud with the CB-01 message; the `no-assignee-check` label is the logged, visible override.
- **MANUAL path changed with no attestation** → `check_attestation.py` fails, names the path and the sign-off required; a false "revert the commit" attestation on an irreversible change is rejected (mirrors `check_rollback`).
- **Companion declared but absent** → existing G-06 path; the offered-install step is what prevents it at init.

## Open questions

- *Resolved 2026-08-17:* **MANUAL attestation** → a committed `attestations/` file is the record for regulated / accuracy-critical paths (durable audit trail); a PR-body `## Attestation` section is accepted for lightweight cases. The ADR fixes the file format and which paths require the committed file (per-path vs per-PR).
- *Resolved 2026-08-17:* **Instruction-sync defaults** → render `CLAUDE.md`, `.cursor/rules/*`, and `AGENTS.md` by default; `GEMINI.md` is interview-gated (rendered only when the team declares Gemini).
- *Resolved 2026-08-17:* **`check_docs_layout.py`** → proposes the move in the audit, then **applies it on approval** — performing the file move AND repointing code/test consumers in one step, never a bare stub.

- Adopt-out shape: its own skill (`/adopt-out`) or an action inside
  `/project-audit`? And where a removal is recorded (a `docs/decisions` /
  `docs/log.md` entry vs a `.framework-state.json` field). Leaning: a
  `/project-audit` action that reuses the doc-layout consumer-scan and records the opt-out as a machine-readable marker in
  `.framework-state.json` — not `docs/log.md` alone: the audit reads state, not
  the log, and `skills/project-audit/SKILL.md` line 77 would otherwise re-flag the
  unwired guard as a finding and recommend restoring what was just disabled.
  `/project-audit` must honor that marker; a `docs/log.md` note accompanies it. (A26)

## Decisions this depends on

- **ADR 00X — a MANUAL/attestation registry tier** (write before capability 4).
- Existing: A2 (registry not duplicated), A11 (guard-local floor), A18 (plugin-declared hooks), P-04 (plan/execute parity), G-06 (companion declarations).

## Phasing (one concern per branch, per CB-02 itself)

1. **Instruction-file sync** — the backbone; unblocks multi-repo + multi-tool coherence.
2. **Collaboration** module + assignee gate + create-and-assign helper.
3. **Documentation + canonical doc-layout** (incl. handoff notes, the `check_doc_links.py` reference-resolution gate promoted from AR-AP, and promote-from-superpowers).
4. **Domain + MANUAL tier** (ADR first).
5. **Ownership** registry (+ generated CODEOWNERS).
6. **Artifact ladder** (lifecycle + remaining templates).

The interview/audit **config layer** (new Round 4 in `/project-init`; matching
`/project-audit` discovery + approval pass) is extended as each capability lands —
a capability isn't "done" until a new *or* retrofit repo can turn it on through
the interview and have the audit report its absence and propose its adoption.

## First learnings feeding this spec (AR-AP audit, 2026-08-16)

The repo->plugin loop above is already live — the AP+AR audit (PR #84) surfaced two refinements before this spec ships:

1. **Doc relocation must repoint executable consumers, not just links** (folded into the artifact-ladder Enforce+promote above). AR-AP keeps 30 specs / 25 plans under `docs/superpowers/{specs,plans}`; a proposed move to `docs/{specs,plans}` with redirect stubs broke content-based tests that read those files (`tests/test_phase6_governance_docs.py`, `scripts/phase3_exit_readiness.py`). The canonical-doc-layout promote step owns this inventory — code and tests, not only cross-doc links.
2. **Audit code-level findings must scope to the affected paths.** AR-AP's audit claimed currency was `float` "end to end," but `canonical_records._money()` and the `reporting_views` rollups already use `Decimal`; only the workbook/report paths are float. `/project-audit`'s money/precision spot-check must report **per-path** (Decimal-correct vs float) and scope any proposed migration to the float paths only — overclaiming inflates the work and erodes trust in the finding. This pairs with the domain/MANUAL money tier (capability 4): accuracy-critical money paths are exactly where a MANUAL attestation belongs, and the audit must locate them precisely rather than sweep correct paths into the change.
3. **Grep is a lead, not a verdict — search the lexicon, corroborate before concluding.** A zero-result grep is not evidence of absence, and a single-term grep is not evidence of presence: the same concept and the same *symptom* wear different words across platforms (money: `amount` / `total` / `price` / `monetaryValue` / `cents` / `Decimal` / `float`; failures: "connection refused" / `ECONNREFUSED` / "tunnel error"). The audit and the code-level scanners search against a **concept-lexicon** (and a symptom-lexicon for troubleshooting), and a finding requires corroboration — read the call site, run the synonym set — before it is written as MISSING or a FINDING. This extends "evidence over recollection" and Rule 0's "a single-file search is not evidence of absence" with the lexicon dimension, and it is how CB-04's false positives are killed before they are recorded rather than by mechanizing intent.
4. **AR-AP already built the migration flow the right way — promote it, don't reinvent.** The relocation the earlier draft feared as a partial, harmful move was in fact complete and correct: PR #85 collapsed `docs/superpowers/* → docs/*` with redirect stubs, and `feat/doc-link-gate` added `tests/test_doc_links.py` — the tree-wide reference-resolution gate above. AR-AP chose the **kit-native `docs/` layout** (so "declarable home" stays a general option, not an AR-AP example) and did the move with repoint-plus-gate — invariant #3 in practice. Two things flow back: (a) `check_doc_links.py`, promoted near-verbatim from AR-AP, becomes the enforcement half of capability 3; (b) the meta-lesson from that gate's own fix commit — "the green came from the file not being there yet, not from the code being right" (the module was untracked, so it was invisible to its own `git ls-files` scan) — is corroborate-before-concluding catching itself, and belongs in the guards / silent-degradation doctrine.
