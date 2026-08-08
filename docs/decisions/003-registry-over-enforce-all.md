# 003 — Document every rule now; track enforcement status rather than gating on it

- **Status:** Accepted
- **Date:** 2026-08-08

## Context
Prose rules are demonstrably ignorable. The tempting response is to refuse to
document a rule until it is mechanically enforced.

## Decision
Document every rule immediately in `REGISTRY.md` with an ID, the layer it should
live in, what enforces it today, and a promote-when trigger. `PROSE` on a
mechanisable rule is tracked debt with a ticket, not a silent gap.

## Alternatives considered

| Option | Why not |
|---|---|
| Enforce-or-omit | The knowledge is lost in the gap between learning a rule and finding time to mechanize it — which is where most rules die. |
| Prose only, no status | The original disease. A rule everyone agrees with, nobody notices is unenforced, and which never fires. |
| Enforce everything immediately | Produces false positives, checks get disabled, and a disabled check protects nothing. |

## Consequences
**Accepted costs:** a registry can lie if not maintained. Mitigated by
`/project-audit` verifying that every row claiming HOOK/TEST/GATE actually has
that check wired.

**Revisit when:** the PROSE column stops shrinking across three consecutive
retros — that means the promote-when triggers are not working.
