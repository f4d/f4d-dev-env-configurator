# Architecture Review — f4d-kit

**Date:** 2026-08-08 · **Version reviewed:** 1.9.0 · **Reviewer:** architecture pass over the full system

---

## What this system actually is

Not a template. A **configuration compiler**: an interview produces a project
configuration, that configuration produces an environment, and the environment
enforces the rules mechanically rather than asking anyone to remember them.

```
Interview ──► Config ──► Environment ──► Enforcement ──► Evidence ──► Interview
  (Q&A)      (profile,   (repo, stack,   (hooks, gates,  (telemetry,   (next
             registry)    CI, docs)       tests)          audit)        project)
```

The loop closing back on itself is the whole design. It is also where the holes are.

**Current surface:** 14 skills · 22 rules modules · 7 hooks · 4 agents · 5 gate
scripts · 8 process docs · 72 registry rules.

---

## Verdict

The **enforcement architecture is sound**. The three-layer model (hook / test /
prose), the registry with honest status tracking, and the evidence-over-memory
principle are the right foundations, and they are unusual — most internal
frameworks stop at the prose layer and never notice.

The **lifecycle architecture has a structural gap**: the system is excellent at
*creating* a correctly-configured project and has almost nothing for *keeping* one
correct as the framework evolves. Everything below flows from that.

---

## Findings

### A1 — No upgrade path. Severity: **critical**

Projects pin a plugin version. There is no mechanism to move a project from
v1.5.0 to v1.9.0. Nothing detects that a repo is behind, nothing migrates its
`.claude/` directory, nothing reconciles its registry against the new one.

**Why this is the worst one:** it is a slow failure. Eight repos scaffolded over
six months will sit at six different versions with six different rule sets, and
the framework's core promise — *"we are always working on the same system"* —
quietly becomes false. Nobody notices, because each repo works.

It also makes every future improvement worth less. A rule promoted to a gate in
v2.0 protects only repos created after v2.0.

**Fix:** a `/framework-upgrade` skill and a `scripts/upgrade.py` that diffs a
project's `.claude/` against the plugin's current templates, classifies each
difference (framework changed / project customized / both — conflict), and
applies the safe ones. Project customizations must survive; that is what makes it
usable more than once.

### A2 — The registry is duplicated per project with no reconciliation. Severity: **high**

`/project-init` copies `REGISTRY.md` and prunes it. Now the framework registry
and N project registries can disagree, with no way to detect it.

This is **S-05 — two guess lists in two places will disagree, and the
disagreement surfaces as a blank rather than a conflict** — committed by the
framework that defines S-05.

**Fix:** the project keeps only a **manifest** — rule IDs held, plus per-rule
local status overrides. The rule text stays in the plugin, single source. A
project's registry view is generated, not stored.

### A3 — No ADRs for the framework's own decisions. Severity: **high**

The framework mandates an ADR for any hard-to-reverse choice. It has made at
least six with none recorded: GitHub over Linear, Actions over Notion Workers,
one hub DB over per-company, prose-plus-registry over enforce-everything-now,
plugin distribution over a repo template, and `hub` as the default mode.

Each has a stated rationale buried in a conversation that will not survive. **The
framework cannot ask projects to do what it does not do itself** — and the first
time someone asks "why not Linear?", the answer is gone.

### A4 — The interview is not resumable. Severity: **high**

`/project-init` runs four rounds and writes ~30 files in one pass. If it is
interrupted — context exhausted, session closed, an interruption mid-scaffold —
all state is lost and the directory is left half-written.

This is the single most likely thing to be abandoned halfway, because it is the
longest single operation in the system.

**Fix:** persist answers to `.claude/.init-state.json` after each round, and make
the scaffold step idempotent so re-running resumes rather than restarts.

### A5 — The scaffolder has no dry run. Severity: **medium**

`/project-init` writes ~30 files with no preview. The registry contains **P-04 —
preview and execute produce the same request set**. The scaffolder has no preview
at all.

**Fix:** `--plan` mode printing the file tree, the modules, and the gates it would
write. Cheap, and it makes retrofit mode far less frightening on a repo with
existing code.

### A6 — Hook composition and precedence are unspecified. Severity: **medium**

Two `PreToolUse` hooks now match `Write` (`guard.sh` and `rule-zero.sh`).
Undefined and undocumented: execution order, what happens when one blocks and the
other passes, and how plugin hooks interact with a project's own
`.claude/settings.json` — merge or override.

This will produce a confusing failure exactly once, at the worst time, on a repo
that adds a local hook.

### A7 — CI gate cost is unbudgeted. Severity: **medium**

Eight jobs per PR, each spinning a container, plus the auto-review action. Across
several active repos this is real minutes and real spend, and no measurement
exists.

Several gates are also near-instant Python scripts that spend more time on
`actions/setup-python` than on the check itself.

**Fix:** collapse the five script gates into one job with one checkout and one
Python setup. Roughly 5× less overhead for identical coverage.

### A8 — Gates are not conditioned on project shape. Severity: **medium**

`check_statelessness.py` will fail on a legitimately single-instance project. The
escape is `STATELESS_SINGLE_INSTANCE=1`, an environment variable that is not set
by the scaffolder and not documented in the generated repo.

**A gate that fires wrongly gets disabled, and a disabled gate protects nothing.**
The scaffolder must write the conditions, since it already knows the answers from
the interview.

### A9 — Rule IDs have no versioning or deprecation. Severity: **low now, high later**

If `S-05` is ever split or renamed, every project registry referencing it breaks
silently — and "silently" is the operative word, since nothing validates that a
referenced ID exists.

**Fix:** IDs are permanent once issued. Superseding uses a new ID plus a
`Superseded by` row. Add an ID-validity check to the gate that already reads the
registry.

### A10 — No measurement of which rules actually fire. Severity: **medium**

`/retro` asks a human what went wrong. Hooks know exactly what they blocked and
how often, and nothing records it.

Without this, pruning is guesswork, and the 400-line budget is enforced by taste
rather than evidence.

**Fix:** hooks append blocks to `.claude/.enforcement-log`; `session_report.py`
reports rules by fire count. A rule that has never fired in six months is a
pruning candidate; one firing daily is a candidate for a *design* fix rather than
a guard.

### A11 — The plugin is a single point of failure with no offline story. Severity: **low**

Every hook path is `${CLAUDE_PLUGIN_ROOT}/...`. If the plugin is not installed,
uninstalled, or the marketplace is unreachable, **every guard silently disappears**
and the project appears fine.

Same failure shape as the `jq` bug, one level up: absence reads as permission.

**Fix:** `/project-audit` asserts the plugin is installed and at the expected
version, and the scaffolder writes a minimal fallback `guard.sh` into the repo
itself so key-safety survives plugin absence.

### A12 — Secret handling is documented but not verified. Severity: **medium**

The framework correctly refuses to run `gh secret set` and tells the user what to
add. Nothing ever checks whether they did. A repo can carry `notion-sync.yml`,
`gates.yml`, and `claude.yml` with no secrets configured — every workflow fails on
first run, or worse, skips silently.

**Fix:** a `preflight` job that asserts required secrets and variables are present
and non-empty, failing with a precise message naming what is missing.

---

## Opportunities

### O1 — Generate the registry view instead of copying it
Follows from A2. The project holds a manifest of IDs; the full text renders from
the plugin on demand. One source, no drift, and a project's registry is always
current with its pinned version.

### O2 — Make the interview incremental rather than monolithic
Follows from A4. Answers persist; the scaffold is idempotent; each round is
resumable. A side benefit: `/project-audit` can then ask the *unanswered*
questions on an existing repo, turning retrofit into a partial interview instead
of a fresh one.

### O3 — Fire-count-driven pruning
Follows from A10. Turn the 400-line rules budget from taste into evidence. Also
surfaces the more interesting signal: a rule firing constantly is usually a
design problem the guard is papering over.

### O4 — A conformance test suite the framework runs against itself
The kit has `tests/hooks_test.sh`. It should also have a test that scaffolds a
throwaway project from each module combination and asserts verify passes on the
empty scaffold. Right now the scaffolder is the least-tested component in a system
whose entire premise is testing.

### O5 — Extract the doctrine as a portable artifact
The rules in `silent-degradation.md`, `guards.md`, and `capability-parity.md` are
the most valuable content here and are the least tied to any tooling. They would
survive a move off Claude Code entirely. Worth keeping them in a form that does
not depend on the plugin.

### O6 — Cross-project rule analytics
Once several repos run the framework, the aggregate is interesting: which rules
fire everywhere (promote to always-on), which never fire anywhere (delete), which
fire in one repo only (a local problem, not a framework one).

---

## Priority

| # | Finding | Severity | Effort | Do |
|---|---|---|---|---|
| 1 | A1 upgrade path | critical | M | now |
| 2 | A3 framework ADRs | high | S | now |
| 3 | A12 secret preflight | medium | S | now |
| 4 | A4 resumable interview | high | M | next |
| 5 | A2 registry as manifest | high | M | next |
| 6 | A7 collapse gate jobs | medium | S | next |
| 7 | A8 gates conditioned on shape | medium | S | next |
| 8 | A5 scaffolder dry run | medium | S | soon |
| 9 | A10 enforcement telemetry | medium | M | soon |
| 10 | A6 hook precedence docs | medium | S | soon |
| 11 | A11 plugin-absence fallback | low | S | soon |
| 12 | A9 ID permanence | low now | S | before v2 |

---

## The one-sentence version

**The system is well-built for day one and under-built for day two hundred** —
every remaining gap is a variant of "what happens when the framework changes and
eight repos do not."
