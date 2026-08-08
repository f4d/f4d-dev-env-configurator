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

**Evidence first — run this before forming any opinion**

```bash
python3 "$CLAUDE_PLUGIN_ROOT/scripts/session_report.py"
```

It reports counts, not recollection: how many sessions started outside the repo
root (and therefore loaded no rules), how often verify actually ran, and whether
the rules set changed mid-window. **If sessions started in subdirectories, every
conclusion about "the rules were ignored" is unreliable for those sessions.** Fix
the load path, then re-read.

If there is no log yet, do not wait for one. Say so, and fall back to the static
checks below — they are available immediately.

**Enforcement layer** — check this before anything else
- Is `SessionStart` wired in `.claude/settings.json`? If not, **every session started outside the repo root has been running with no rules loaded.** Report this first; it invalidates any conclusion that "the rules were ignored."
- Are `rule-zero.sh` and `done-check.sh` wired?
- For each rule in `.claude/rules/`, ask: is this mechanically enforceable, and is it enforced? List every enforceable-but-prose rule. That list is the real audit finding.
- Are there near-duplicate files suggesting Rule 0 was not in force — `*V2`, `*-final`, `*-new`, `*-copy`, `*-updated`?

**Registry honesty** — the highest-signal check in this audit
- Does `.claude/rules/REGISTRY.md` exist?
- For every row claiming `HOOK`, `TEST`, or `GATE`: **confirm that check actually exists and runs.** A registry asserting enforcement that is not wired is worse than no registry — it makes the gap invisible.
- For every row marked `PROSE` with a promote-when trigger: has the trigger fired? List those. That list is the promotion backlog.
- Run each gate script directly and report pass/fail:
  `python3 .github/scripts/check_fixtures.py`, `check_contract_pin.py`, `check_guess_lists.py`

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
- Any `catch` returning an empty collection — then grep that collection's consumers for **counts and comparisons**, not just renderers
- Any test iterating a collection without first asserting it is non-empty (vacuous pass)
- Any raw identifier reaching user-visible output
- Any hardcoded list of values the source could report live (guess list), and whether two such lists exist for the same question

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
