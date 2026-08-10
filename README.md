# f4d-kit

> **Picking this up mid-stream?** Read `docs/BACKLOG.md` first. It carries every
> open finding, blocked item, and working agreement in resumable form.

A reusable baseline development and code product management framework, delivered as a Claude Code plugin. Install it into any repo — new or inherited — and get the same process, conventions, guardrails, and scaffolding every time.

Built for the shape of work it is most often used on: **API-based, DB-backed web apps implementing custom logic over multi-source data integrations.** Nothing in it is specific to any one project. Modules are opt-in per repo.

---

## Two halves

### Product management — how work gets decided

| Skill | Use when |
|---|---|
| `/work-intake` | Something new arrives and it's unclear where it goes |
| `/write-spec` | A medium or large feature needs defining before it's built |
| `/decision-record` | A hard-to-reverse choice is being made |
| `/ship-it` | A branch is done and needs to go out |
| `/retro` | Monthly, or after something went wrong |

### Development — how work gets built

| Skill | Use when |
|---|---|
| **`/repo-builder`** | **Start here for anything new** — creates the repo, interviews, scaffolds, wires CI, pushes |
| `/org-profile` | First project for a company, or org-level facts changed |
| `/project-init` | New repo, or retrofitting an existing one |
| `/project-audit` | Checking a repo against the framework |
| `/new-module` | Adding a feature slice |
| `/new-integration` | Adding an external data source |
| `/contract-first` | Changing a shape shared across repos |
| `/notion-sync` | Create the Work DB, wire a repo, triage, or query what's in flight |
| `/framework-upgrade` | A repo is behind on plugin version, or the framework shipped a change |
| `/promote-rule` | Move a rule up the enforcement ladder and keep the registry honest |

### Supporting

- `templates/rules/` — 17 composable rules modules, included only when the interview justifies them
- `templates/process/` — lifecycle, definitions, spec/ADR/PR templates
- `templates/scaffold/` — CLAUDE.md, compose, CI, reset script
- `hooks/guard.sh` — hard-blocks secrets, mainnet RPC, force-push, destructive SQL
- `hooks/format.sh` — formats on write, per language
- `agents/` — schema reviewer, integration auditor, contract drift checker, verify runner

---

## The lifecycle

```
Intake → Spec → Decide → Build → Review → Ship → Learn
  │        │       │        │        │       │       │
issue    spec    ADR     branch    agents   PR    rule change
```

Nothing skips a stage; small work just moves through them fast. Full detail in `templates/process/LIFECYCLE.md`.

---

## Install

The kit lives at **`f4d/f4d-dev-env-configurator`** (private). Get a working copy:

```bash
gh repo clone f4d/f4d-dev-env-configurator
```

Then in any project repo:

```bash
cd <project>
claude
```

`/plugin` → add marketplace → point at `f4d/f4d-dev-env-configurator` → install.

---

## Use

```
Anything new     →  /repo-builder     (front door — calls the three below in order)
New company      →  /org-profile      (once per company)
New repo         →  /project-init     (reads the profile, skips what it answers)
Inherited repo   →  /project-audit  then  /project-init  (retrofit mode)
New request      →  /work-intake
Feature (M/L)    →  /write-spec
Structural call  →  /decision-record
Building         →  /new-module  |  /new-integration  |  /contract-first
Finishing        →  /ship-it
Monthly          →  /project-audit  then  /retro
```

---

## Principles

1. **Ask company facts once.** Org profiles hold GitHub org, conventions, stack defaults, automation, and constraints. Projects inherit; they never re-ask.
2. **Interview, don't assume.** Storage, money, blockchain, and frontend modules are opt-in per project. Nothing is inherited by default.
3. **CLAUDE.md is a router, not a manual.** Under 80 lines. Detail lives in `.claude/rules/`, loaded only when relevant.
4. **Hooks over instructions.** Rules are for what Claude should do. Hooks are for what it must never do.
5. **One verify command,** written identically in three places, run before every commit.
6. **Specs and decisions are append-only.** Rules are the living present and stay small — under ~400 lines per repo.
7. **The framework improves through `/retro`.** Anything gotten wrong twice becomes a rule; anything true across repos gets promoted here and the version bumps.

---

## Versioning

Projects pin a plugin version. `/project-audit` reports when a repo is behind. Promote a rule from a project into `templates/rules/` only after it has proven itself in at least one repo.
