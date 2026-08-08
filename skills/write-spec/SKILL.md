---
name: write-spec
description: Write a numbered project spec before building — problem, success criteria, explicit non-goals, data model, external systems, and failure modes. Use for any medium or large feature, whenever the user says "let's build X" without a written spec, or asks to plan, scope, or think through a feature. Also use to bring an existing vague idea up to the Definition of Ready.
---

# Write Spec

A spec exists to move the disagreement earlier. Its job is to be argued with.

## Process

1. Find the next number: `ls docs/specs/ | sort | tail -1`
2. Draft from `${CLAUDE_PLUGIN_ROOT}/templates/process/SPEC.template.md`
3. Fill what you can from the conversation. Ask about the rest — **in one batch, not one at a time**
4. Check against the Definition of Ready in `templates/process/DEFINITION.md`
5. Write `docs/specs/NNN-<slug>.md` with `Status: Draft`
6. Report which Ready criteria are unmet. Do not mark it Ready yourself.

## The questions that actually need asking

Most of the template you can infer. These you cannot:

- **What is explicitly not in scope?** Ask directly. An empty Not-doing list means the scope is undefined, not unlimited.
- **How would we know this failed?** Sharper than asking how we'd know it succeeded.
- **Which source of truth wins?** For anything touching multiple systems. If undecided, that is an ADR, and the spec is blocked on it.
- **What happens when <dependency> is down?** Ask per external system. "It errors" is incomplete — errors to whom, and what do they do next?

## Rules

- The Problem section names no technology. If it does, a solution has been assumed.
- Success criteria are observable by someone outside the work. "Better performance" fails; "p95 under 300ms on the list endpoint" passes.
- Never fill Open Questions with guesses. An unanswered question is information; an invented answer is a bug with a paper trail.
- Specs are append-only. Superseding one means a new number and a `Superseded by` line on the old — never an edit that makes history lie.
- If the spec is getting long, the feature is too big. Split it into two specs before writing more.
