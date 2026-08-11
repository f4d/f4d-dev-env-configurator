---
name: retro
description: Run a retrospective that converts what went wrong into rule changes. Use monthly, after any incident, after a project milestone, or when the user says "retro", "what did we learn", "this keeps happening", or notices they have corrected Claude on the same thing more than once.
---

# Retro

The only retro output that matters is a changed rule. A retro that changes nothing was either a genuinely clean period — say so — or an hour wasted.

## Gather

1. `git log --since="1 month ago" --oneline` — what actually shipped
2. `docs/specs/` — anything Draft for over a month? That's a signal, not a backlog.
3. `docs/decisions/` — any decision whose Revisit-when condition has been met?
4. `CHANGELOG.md` — anything shipped and then immediately patched?
5. **Ask the user directly:** *"What did you have to explain to me more than once this month?"*

Question 5 produces more value than the other four combined.

## Analyze

**First question for every violated rule: was it even in context?**
Run `python3 "$CLAUDE_PLUGIN_ROOT/scripts/session_report.py"` — it answers this
with counts rather than memory. Check the load path before diagnosing
inattention — with **evidence** (`/context` shows what actually loaded), not
doctrine: current Claude Code auto-loads `CLAUDE.md` and unscoped
`.claude/rules/*.md`. A rule absent from context needs an observed cause — a
setting-source exclusion, an old CLI, a path-scoped rule that never matched —
and that cause is the finding, not the rule.

**Also read the fire counts** (A10): `session_report.py` prints denies by rule
ID from `.claude/.enforcement-log`. A rule firing constantly is usually a
design problem the guard is papering over — fix the design, not the message. A
rule that has never fired across many sessions is a prune candidate. Any
`UNREGISTERED` fires mean the guard enforces something the registry holds no
row for — a registry-honesty gap to resolve.

**Second question: which layer should this have been in?**
A rule that was in force and did not fire is usually mis-classified, not
under-emphasized. Restating it more firmly changes nothing.

| Problem | Fix belongs in |
|---|---|
| Claude keeps making the same mistake | A rule in `.claude/rules/` |
| Claude does something dangerous | A hook — rules are advisory, hooks are not |
| Repetitive work done slightly differently each time | A skill |
| Same review comment on many PRs | A rule, or an audit agent check |
| A decision keeps getting re-argued | An ADR |
| A whole class of bug ships repeatedly | A Definition of Done line |

**Rules are for things Claude should do. Hooks are for things Claude must never do.** If the consequence is expensive or irreversible, it belongs in a hook.

Read `templates/process/ENFORCEMENT.md` for the full model and this framework's own audit of which of its rules are still prose that should not be.

## Promote

For each mis-classified rule, run `/promote-rule` with its ID. That skill owns
building the check red-first, wiring it, and updating the registry. Do not
restate a rule more firmly — that has already been tried and is what produced
this retro.

## Prune

Adding is easy; this part is not. For each existing rule ask: *has this earned its context this month?* A rule nobody violated and nobody needed is a candidate to cut. Keep the total under ~400 lines.

## Promote

If a rule would help more than one repo, move it into `f4d-kit/templates/rules/`, bump the plugin version, and note which repos should re-pin. This step is what makes the framework compound instead of ossify.

## Write

Append to `docs/log.md`:

```markdown
## YYYY-MM
**Shipped:** <one line>
**Recurring problems:** <list>
**Changes made:** <rule/hook/skill added, changed, or removed>
**Promoted to f4d-kit:** <none, or what and why>
**Watching:** <not yet a pattern, but noticed twice>
```

The Watching section is how you tell a fluke from a pattern next month.
