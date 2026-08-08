---
name: work-intake
description: Triage an incoming request, idea, bug report, or feature ask into the right lane — classify it, size it, and route it to a spec, a ticket, or a decision record. Use whenever the user describes something they want built, reports a problem, or dumps a list of ideas, and it is not yet clear whether it needs a spec. Also use when the user asks "what should I work on", "where does this go", or pastes a backlog.
---

# Work Intake

Prevent two expensive failures: building without a decision, and re-arguing a decision already made.

## Classify

| Class | Signal |
|---|---|
| **Bug** | Existing behavior contradicts stated or reasonable expectation |
| **Chore** | No behavior change — deps, cleanup, config, tooling |
| **Feature** | New or changed behavior |
| **Question** | Answer may dissolve the request entirely. Answer it before anything else. |

Answer Questions immediately. Roughly a third of them evaporate on contact.

## Size by uncertainty, not hours

- **S** — the finished state fits in one sentence and you'd bet on it
- **M** — you know what to build, not exactly how
- **L** — the approach itself is in question, or it touches more than one system or repo

## Route

| Class + size | Goes to |
|---|---|
| Bug | Build. Write the failing test first. |
| Chore | Build. |
| Feature S | Build, with a one-paragraph intent in the issue |
| Feature M or L | `/write-spec` |
| Anything with an expensive-to-reverse choice | `/decision-record` first, then spec |

## Where it lands

If the company has a Notion Work DB (check the org profile for `notion_work_db`):
- The item is already a row if it came from a GitHub issue — the sync created it in `Stage: Triage`
- If it did not come from GitHub, create the GitHub issue first and let the sync produce the row. Do not create an orphan Notion row; a row with no issue number cannot be tracked to a commit.
- Write `Class`, `Size`, `Priority`, `Area`, and `Stage`. Never touch the GitHub mirror fields.

If there is no Work DB, fall back to a GitHub issue with labels.

## Before routing, check

- **Has this been decided before?** Search `docs/decisions/`, `docs/specs/`, and the Work DB for a similar closed item. If yes, surface it and ask whether the context has changed. Do not re-open silently.
- **Is this actually two items?** Most L items are an M and an S wearing a trench coat. Split them.
- **Is this a rule, not a feature?** "Claude keeps doing X" is not a ticket. It is a line in `.claude/rules/`. Route it there.

## Output

```
CLASS:  Feature
SIZE:   M
ROUTE:  /write-spec
PRIOR:  docs/decisions/004-postgres.md — related, still holds
SPLIT:  none
```

Then do the routed thing, or ask which item to start with if several came in at once. Never start building from intake directly on an M or L.
