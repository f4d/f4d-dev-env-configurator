---
id: livesystem
always_apply: false
---
# Live System

This repo has production users. Assume every change is observed.

- Production credentials never enter an agent session. Local and staging only.
- No destructive migration without an explicit written plan: expand → backfill → contract, across separate deploys.
- Never drop or rename a column in the same release that stops writing to it.
- New fields are nullable or defaulted. Never add a NOT NULL column to a populated table in one step.
- Feature-flag anything that changes existing user-visible behavior.
- Every change lists its rollback step before it merges. "Revert the commit" is only valid if no migration ran.
