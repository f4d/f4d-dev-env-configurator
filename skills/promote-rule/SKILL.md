---
name: promote-rule
description: Move a rule up the enforcement ladder — prose to test, test to hook, or project-local to framework-wide — and keep the rule registry honest. Use when a rule was violated despite being written down, when /retro identifies a mis-classified rule, when a project-local rule proves useful across repos, or when the user says "make this a hook", "this should fail the build", or "promote this rule".
---

# Promote Rule

The framework improves by rules moving **up** the ladder and dead rules moving
off it. Without this step, `/retro` produces observations nobody acts on.

Ladder: `PROSE → LINT → TEST → GATE → HOOK`. Higher is harder to ignore.

---

## 1 — Identify

Find the rule in `.claude/rules/REGISTRY.md` by ID. If it has no ID, it is not a
tracked rule yet — add it to the registry first, with an honest current status.

Ask the question that decides everything:

> **Was the rule in context when it was violated?**

Run `python3 "$CLAUDE_PLUGIN_ROOT/scripts/session_report.py"` and check
`/context` for what actually loaded. Current Claude Code auto-loads `CLAUDE.md`
and unscoped `.claude/rules/*.md`; if the rule genuinely wasn't in context
(setting-source exclusion, old CLI, path-scoped rule that never matched), the
fix is the load path, **not** a promotion. Promoting a rule that was never read
solves nothing and adds a check nobody understands.

---

## 2 — Choose the target layer

| The failure | Target |
|---|---|
| Expensive or irreversible if it happens once | **HOOK** — exit 2 |
| Detectable from the diff, at PR time | **GATE** — CI job |
| Detectable from code behavior | **TEST** |
| Detectable from source shape | **LINT** |
| Requires judgment about intent | Stays **JUDGMENT** — stop here |

Do not promote a judgment rule. You will get false positives, someone will
disable the check, and you will be worse off than with prose.

---

## 3 — Build it red first

Non-negotiable (G-01):

1. Write the check
2. **Break the code deliberately. Confirm the check fails.**
3. Restore
4. Confirm it passes

A check that has never gone red has proved nothing. State in the PR that you did
this and what you broke.

Reference implementations: `${CLAUDE_PLUGIN_ROOT}/templates/tests/` for tests,
`hooks/` for hooks, `scripts/check_*.py` for gates.

---

## 4 — Wire it

| Layer | Where |
|---|---|
| HOOK | `.claude/settings.json` + `hooks/`, and a case in `tests/hooks_test.sh` including the **fail-loud** path |
| GATE | a job in `.github/workflows/gates.yml`, named with its rule IDs |
| TEST | the project suite, run by verify |
| LINT | the linter config |

---

## 5 — Update the registry

Change the rule's `Today` column and clear its promote-when trigger. **The
registry is the deliverable** — an un-updated registry is worse than none, because
it asserts a state that is no longer true.

---

## 6 — Promote to the framework, if it generalizes

If the rule would help more than one repo:

```bash
cd <f4d-kit>
# add the rule to templates/rules/<module>.md and REGISTRY.md
# add the check to scripts/ or hooks/ or templates/tests/
bash tests/hooks_test.sh          # must pass
git add -A
git commit -m "feat(rules): promote <ID> from PROSE to <LAYER>"
# bump minor in .claude-plugin/plugin.json, add a CHANGELOG entry
git push
```

Then list which repos should re-pin. `/project-audit` reports a repo behind on
plugin version.

**Promote only after a rule has proved itself in at least one repo.** A rule
invented at framework level and never used in anger is speculation.

---

## Demotion is also promotion's job

For each rule that has not fired in six months, ask: is it load-bearing, or is it
costing context on every turn for nothing? Cut it. Keep `.claude/rules/` under
~400 lines. Record the removal in `docs/log.md` so it is not silently
re-introduced later.
