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
   assign-before-branch, one-concern-per-branch, one-linked-item-per-PR,
   push-on-cadence, no-force-push-shared. Always-on for multi-person repos only.
2. **Instruction-file sync** (`render_instructions.py` + `check_instruction_honesty.py`)
   — rule-module frontmatter is the single source; render to CLAUDE/AGENTS/GEMINI/Cursor
   in delimited managed blocks; `--check` fails on drift. Backbone the rest ride on.
3. **Documentation + canonical doc-layout** (`documentation.md` + templates +
   `check_docs_layout.py`) — product docs, end-user how-tos, operations runbooks,
   handoff/session notes, AND the artifact-ladder layout map + enforce/promote
   (below). Opt-in by lifespan/production status.
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
- CB-03 (diff-vs-intent) stays JUDGMENT; mechanizing it yields false positives.

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
promote step is what makes the design doc durable and shared. Relocation is never just a file move: scripts and tests routinely hard-code doc paths — observed live in AR-AP PR #84, where `scripts/cross_phase_quality_gates.py` and `tests/test_phase6_governance_docs.py` read files under `docs/superpowers/plans/`. `check_docs_layout.py` therefore inventories the **executable and test consumers** of any path it proposes to move, and the promote step repoints them; a redirect stub alone leaves a content-based test reading a five-line stub and failing. Repoint code and tests, not only cross-doc links.

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
  `check_assignee.py`, `check_attestation.py`, `check_docs_layout.py`, and
  `gen_codeowners.py` (13 → ~18 gate/helper scripts).
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

- MANUAL attestation storage: PR-body section (proposed) vs a committed `attestations/` file for audit trails on regulated paths. Decide in the ADR.
- Instruction-sync default tool set: render AGENTS.md + GEMINI.md by default, or interview-gate each tool? (Leaning: default Claude + Cursor + AGENTS.md; GEMINI.md gated.)
- Does `check_docs_layout.py` *move* promoted docs or only *propose* the move for the human to run? (Leaning: propose in audit, apply on approval — consistent with the interaction model.)

## Decisions this depends on

- **ADR 00X — a MANUAL/attestation registry tier** (write before capability 4).
- Existing: A2 (registry not duplicated), A11 (guard-local floor), A18 (plugin-declared hooks), P-04 (plan/execute parity), G-06 (companion declarations).

## Phasing (one concern per branch, per CB-02 itself)

1. **Instruction-file sync** — the backbone; unblocks multi-repo + multi-tool coherence.
2. **Collaboration** module + assignee gate + create-and-assign helper.
3. **Documentation + canonical doc-layout** (incl. handoff notes + promote-from-superpowers).
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
