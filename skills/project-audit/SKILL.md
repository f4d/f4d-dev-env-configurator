---
name: project-audit
description: Audit an existing repo against the f4d-kit framework and report what is missing, drifted, or misconfigured — rules, hooks, verify command, CI, seed quality, adapter coverage. Use when the user asks to "rightsize", "audit", "check this repo", "why does Claude keep getting this wrong here", or before adopting an inherited codebase. Also use periodically on projects already scaffolded, to catch drift.
---

# Project Audit

Read-only. Report, then ask before changing anything.

## Checks

**Org alignment**
- Is there an org profile for this project's company at `~/.claude/f4d/orgs/`? If not, run `/org-profile`.
- Does `.claude/rules/org.md` exist and match the profile's current `constraints` block? Report drift in either direction.
- Do this repo's conventions match the org profile — webhook prefix, package scope, env prefix, default branch?
- Is this repo on the org Project board if the profile says `coherence: shared`?

**Config presence**
- `CLAUDE.md` exists, is under 80 lines, has no unfilled `{{TOKEN}}`
- `.claude/rules/` exists and the modules match what the project actually does
- `.claude/settings.json` wires the guard hook
- `.gitignore` covers `.env`, `*.key`, `*.pem`

**Verify integrity**
- A single verify command exists
- It is identical in CLAUDE.md, the script, and CI
- It passes right now — run it

**Rules vs reality** — the highest-value section
- Does the repo have integrations but no `data-integration.md`?
- Object storage but no `storage.md`?
- Money math but no `money.md`?
- Production traffic but no `livesystem.md`?
- Conversely: any module present for something the repo does not do? Remove it — dead rules cost context on every turn.

**Code-level spot checks**
- Any test that calls a live external API
- Any `float` in a currency path
- Any FK without an index
- Any outbound call without a timeout
- Any log line that could emit a payload or credential
- Seed data: does it contain nulls, unicode, and boundary values, or only happy-path rows?

## Output

```
REPO:       <name>
FRAMEWORK:  present | partial | absent
VERIFY:     PASS | FAIL | MISSING

MISSING     (should exist, does not)
DRIFTED     (exists, disagrees with itself or with the code)
UNNEEDED    (present, project does not need it)
FINDINGS    (code-level, with file:line)
```

Rank everything by what will bite soonest. Then ask: *"Want me to fix these, or start with the top three?"* Never fix unasked.
