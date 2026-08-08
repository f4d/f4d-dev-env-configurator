---
name: project-init
description: Interview the user about a new or existing software project, then scaffold or retrofit its full Claude development environment — CLAUDE.md, rules modules, hooks, subagents, verify commands, local stack, and contract layer. Use this whenever the user starts a new repo, says "new project", "set up a project", "scaffold this", "rightsize this repo", "get this project ready for Claude", "add rules/hooks to this repo", or when they are about to begin building an API-based, DB-backed web app. Also use when an existing repo has no CLAUDE.md, no .claude/ directory, or inconsistent conventions compared to their other projects.
---

# Project Init

Scaffold a Claude development environment sized to what the project actually is. Two modes:

- **NEW** — empty or near-empty directory. Full scaffold.
- **RETROFIT** — existing code. Detect what's there, add what's missing, change nothing that works.

Detect mode by checking for `package.json`, `pyproject.toml`, `.git`, and existing source directories. State which mode you're in and confirm before proceeding.

---

## Step 1 — Interview

Ask in **four rounds**. Do not dump all questions at once. After each round, state what you've concluded so the user can correct you cheaply.

Use `ask_user_input_v0` if available; otherwise ask as prose, one round per message.

### Round 0 — Company & project identity (always first)

```bash
ls ~/.claude/f4d/orgs/
```

1. **Which company is this project for?**

**If a profile exists** for that company: read it, state the defaults it supplies in one line, and move to Round 1. Do not re-ask anything it answers.

**If no profile exists:** run `/org-profile` now, then return here. Company-level facts are captured once per company — GitHub org, conventions, stack defaults, automation settings, and constraints — and every project in that company inherits them.

Then ask the project-identity questions the profile cannot answer:

2. **Project name and repo slug?**
3. **Is this project shared with the rest of this company's work, or siloed from it?** — decides whether it joins the org Project board and shares cadence. Default to the company's `coherence` setting; ask only to confirm.
4. **Who is this for — internal, a named client, or a product with outside users?**
5. **Expected lifespan?** — `throwaway / experiment` | `ongoing product` | `client deliverable with a handoff`
6. **Where is this project's work tracked?** — the hub-mode branch:

   | Answer | Meaning | Cost |
   |---|---|---|
   | **`hub`** *(default)* | The central Work DB in the hub workspace only. `Company` and `Project` segment it. | None |
   | **`hub+local`** | Hub row is canonical, mirrored into that company's own workspace | A second sync target to maintain |
   | **`local`** | That company's own workspace only, no hub row | Loses cross-company roll-up |

   Default to `hub` unless the company profile says otherwise. Propose it rather than asking open-ended: *"Tracking in the hub, same as everything else — or does this one need its own workspace?"*

   Choose `hub+local` only when someone **outside your workspace** needs to see status. Choose `local` only for contractual isolation. Both are real maintenance; `hub` is free.

   Whatever is chosen becomes `Hub Mode` on every row this project creates, and is recorded in the org profile so the question isn't re-asked per project in that company.

Question 5 matters more than it looks. A throwaway gets core rules and nothing else. A client deliverable with a handoff needs documentation, a README written for a stranger, and no dependencies the client can't maintain.

Carry into every later step: the company's `constraints` block goes into `.claude/rules/org.md` verbatim, and its conventions (webhook prefix, package scope, env prefix) apply without asking.

### Round 1 — Shape (always ask)

1. **What does this project do, in one or two sentences?**
2. **Primary language for the backend?** — `python` / `typescript` / `both` / `other`
3. **Is there a user-facing frontend?** — `none, API only` / `SSR web app` / `SPA` / `admin UI only`
4. **Database?** — `postgres` / `sqlite` / `mongo` / `none yet` / `other`

### Round 2 — Integration surface (always ask)

5. **What external systems does this talk to?** List them. For each, note whether it is: read-only, write, or both; and whether it is metered/paid.
6. **Does anything call *in* — webhooks, callbacks, third-party pushes?**
7. **Is this standalone, or part of a group of repos that must agree on a contract?**
8. **Is any part of this already live / in production?**

### Round 3 — Conditional modules

Only ask what applies, based on Rounds 1–2. Each YES pulls in a rules module and its associated tests, hooks, and local-stack pieces.

| Ask when | Question | Enables module |
|---|---|---|
| Any file input/output mentioned | **Does this project store or serve user files? If so, where — S3/R2, local disk, DB blobs?** | `storage` |
| Storage = yes | **Do files need content-addressing, dedupe, or reproducible hashes?** | `determinism` |
| Money, pricing, invoices, splits, payouts mentioned | **Does this project compute or move money?** | `money` |
| Chain, wallet, mint, token, contract mentioned | **Any blockchain or smart-contract component? Which chains?** | `blockchain` + `keysafety` |
| Multiple sources in Q5 | **Do you need to reconcile or merge data across those sources into one canonical record?** | `data-integration` |
| Frontend != none | **Any hard performance or accessibility requirements?** | `frontend` |
| Q8 = yes | **What in production must never break, and what must never be touched by an agent session?** | `livesystem` |
| PII, health, payment data hinted | **Does this hold personal, payment, or regulated data?** | `dataprotection` |

**Rule:** never assume a module. If storage wasn't mentioned, ask — don't skip and don't include. Storage is configured per project, never inherited by default.

**Exception — always included, never asked about:** `core`, `guards`, `silent-degradation`. These address the failure class that survives review, and a project that opts out of them has opted out of the point of the framework.

---

## Step 2 — Confirm the plan

Before writing anything, print a table and wait for approval:

```
ORG:       F4 Digital (f4d)  — profile found, defaults applied
PROJECT:   invoice-sync  |  shared with org board  |  client deliverable
MODE:      NEW
STACK:     Python 3.12 (FastAPI) + TypeScript (Next.js) + Postgres
MODULES:   core, api, database, python, typescript, data-integration, storage
SKIPPED:   determinism, money, blockchain, keysafety, frontend-perf, livesystem
HOOKS:     guard.sh (secrets, prod), format.sh
AGENTS:    contract-drift-checker, schema-reviewer, integration-auditor
VERIFY:    uv run ruff check . && uv run mypy . && uv run pytest && pnpm typecheck && pnpm test
LOCAL:     docker compose — postgres 16, mailpit, minio (R2-compatible)
```

Ask: *"Anything to add or drop before I write it?"*

---

## Step 3 — Write the scaffold

Read `references/scaffold-spec.md` for exact file contents and layout. Write in this order:

1. `.gitignore`, toolchain pins (`.python-version`, `packageManager`)
2. `CLAUDE.md` — assembled from `templates/scaffold/CLAUDE.md.tmpl`, **kept under 80 lines**
3. `.claude/rules/org.md` — the company's `constraints` block, copied verbatim from its org profile
4. `.claude/rules/*.md` — copy only the selected modules from `${CLAUDE_PLUGIN_ROOT}/templates/rules/`, **plus `REGISTRY.md` always**. Then prune the registry to the rules this project actually holds, and set each row's `Today` column to what genuinely enforces it here. A registry asserting checks that do not exist is worse than none.
5. `.claude/settings.json` — hooks wired, **including `SessionStart`**. This is not optional: without it, a session started in any subdirectory never loads the repo-root instruction files at all. See `templates/process/ENFORCEMENT.md`.
6. `.claude/agents/*.md` — only the selected agents
7. `docker-compose.yml` + `scripts/dev-reset.sh`
8. `verify` script in `package.json` and/or `Makefile`
9. `.github/workflows/` — `verify.yml` running the same command, plus `claude.yml`, `claude-code-review.yml`, and `notion-sync.yml` from `${CLAUDE_PLUGIN_ROOT}/templates/github/` if the org profile has `claude_github_app: installed` and `notion_work_db` set. Copy `scripts/notion_sync.py` to `.github/scripts/`.
   Also write `.github/ISSUE_TEMPLATE/bug.yml` and `feature.yml` — structured enough that `@claude` can act on a report directly.
10. **Process layer** — always, regardless of project size:
   - `docs/specs/`, `docs/decisions/`, `docs/log.md`, `docs/intake.md`
   - `docs/LIFECYCLE.md`, `docs/DEFINITION.md`, `docs/ENFORCEMENT.md`, and `docs/TEST_STRATEGY.md` copied from `${CLAUDE_PLUGIN_ROOT}/templates/process/`
   - `tests/hooks_test.sh` copied from the kit, and wired into the verify command
   - `templates/tests/guard_tests.{py,ts}` copied to the project suite — S-01 and S-02 apply to every project
   - `.github/workflows/gates.yml` plus `scripts/check_*.py` copied to `.github/scripts/` — only the jobs whose rules this project holds. Delete the rest; a gate for a rule the project does not have will fail confusingly.
   - `.gitignore` entry for `.claude/.session-log` and `.claude/.last-verify` — local telemetry, not shared state
   - `.github/pull_request_template.md` from `PR.template.md`
   - `docs/decisions/001-stack.md` — write the ADR for the stack chosen in this interview. The first decision is always the stack, and it is always worth recording.
11. `README.md` — human-facing, distinct from CLAUDE.md
12. First commit

**Critical:** `CLAUDE.md` loads on every turn. Keep it to the architecture map, the commands, and the non-negotiables. Everything else goes in `.claude/rules/` where it loads only when relevant.

---

## Step 4 — Prove it works

Do not declare done until:

```bash
./scripts/dev-reset.sh   # stack comes up, migrations run, seed loads
<verify command>          # passes on the empty scaffold
git log --oneline -1      # scaffold commit exists
```

If the verify command fails on an empty scaffold, fix the scaffold — never loosen the check.

---

## Step 5 — Report

Print the file tree written, the verify command, and **the three things the user must fill in themselves** (credentials, the real schema, the first endpoint). Then stop. Do not start building features.

---

## RETROFIT mode differences

- **Detect before asking.** Read `package.json`, `pyproject.toml`, existing dirs, and any current `CLAUDE.md`. Bring findings to Round 1 so the user is correcting, not typing.
- **Never overwrite an existing `CLAUDE.md`.** Write `CLAUDE.md.proposed` and show a diff.
- **Adopt existing conventions** over template defaults. If the repo uses `npm` and 4-space Python indents, the rules encode that. The framework is for consistency going forward, not for reformatting history.
- **Run the verify command first.** If it fails on existing code, report the failures and ask whether to fix or to baseline them — do not silently weaken the config.
- Ask additionally: *"What in this repo currently annoys you, or what does Claude keep getting wrong?"* Those answers become the most valuable rules in the file.

---

## Reference files

- `references/interview-guide.md` — how to read ambiguous answers, follow-ups worth asking
- `references/scaffold-spec.md` — exact file contents per module
- `references/module-catalog.md` — what each rules module contains and what it costs
- `${CLAUDE_PLUGIN_ROOT}/templates/org/ORG.template.yml` — the org profile schema this reads from
