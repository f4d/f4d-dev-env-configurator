---
name: decision-record
description: Write an architecture decision record capturing a choice, the alternatives that lost, and why. Use whenever a hard-to-reverse choice is being made — datastore, auth model, vendor, canonical-record precedence, public API shape, language boundary, hosting — or when the user asks "should we use X or Y" about something structural. Also use to reconstruct an undocumented decision already made.
---

# Decision Record

## When this applies

Write an ADR when reversing the choice in six months would cost more than a day.

**Yes:** datastore, auth model, a vendor you'll build against, which system owns a field, public API shape, sync vs async boundary, monorepo vs separate repos, hosting.

**No:** library choices you could swap in an afternoon, naming, file layout, formatting.

When unsure, ask: *"if this turns out wrong, is it a fix or a rewrite?"* Rewrite means ADR.

## Process

1. Next number from `ls docs/decisions/`
2. Draft from `${CLAUDE_PLUGIN_ROOT}/templates/process/ADR.template.md`
3. **Fill Alternatives first.** If you can only name one option, you have not made a decision — you have made an assumption. Go find at least two more.
4. Write the decision as one sentence, present tense, active voice
5. Fill Consequences honestly — especially Reversal cost
6. Save as `docs/decisions/NNN-<slug>.md`, `Status: Proposed`
7. Link it from any spec that depends on it

## What makes an ADR worth writing

The Alternatives table. Six months out, the question is never "what did we choose" — the code answers that. It is always "did we consider X, and why not?" An ADR that lists one alternative dismissed as "worse" is worthless. Give the specific reason it lost: a cost, a constraint, a limit you hit.

## Reconstructing an old decision

If a choice was made without a record, write the ADR retroactively with `Status: Accepted` and a note that it was reconstructed. Mark anything uncertain as uncertain rather than inventing a rationale. A reconstructed ADR with honest gaps beats a confident fiction.
