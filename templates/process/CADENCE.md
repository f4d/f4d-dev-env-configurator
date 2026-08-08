# Cadence

Small, fixed rhythms. The point is that reviews happen when nothing is wrong, so that finding something wrong is normal rather than alarming.

| When | What | Skill | Output |
|---|---|---|---|
| Per work item | Intake → classify | `/work-intake` | Issue, correctly sized |
| Per M/L feature | Spec | `/write-spec` | `docs/specs/NNN-*.md` |
| Per irreversible choice | ADR | `/decision-record` | `docs/decisions/NNN-*.md` |
| Per PR | Audit agents, then human review | `verify-runner` + relevant auditor | Approval |
| Per merge | Version, changelog, rollback note | `/ship-it` | Deploy |
| Monthly, per repo | Framework + code audit | `/project-audit` | Findings, ranked |
| Monthly, across repos | What did we learn | `/retro` | `docs/log.md` entry, rule changes |
| Quarterly | Framework version review | manual | `f4d-kit` bump, repos re-pinned |

## Monthly review, in order

1. `/project-audit` on each active repo
2. Collect: what did Claude get wrong repeatedly, what did a human have to explain twice
3. `/retro` — turn the top two into rules; delete any rule that hasn't earned its context
4. If a rule generalizes beyond one repo, promote it into `f4d-kit/templates/rules/` and bump the plugin

Step 4 is what makes this a framework instead of a folder of good intentions.

## Rules budget

A repo's `.claude/rules/` should stay under ~400 lines total. When it exceeds that, you are not more disciplined — you are paying context on every turn for rules Claude has stopped reading carefully. Cut or consolidate before adding.
