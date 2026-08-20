---
id: capability-parity
always_apply: false
---
# Capability Parity

For any project where a UI, an API, and an external contract must stay aligned.

## The UI is the proof of alignment

- An unconsumed capability appears as a **blocked or disabled control carrying its reason** — legible on screen, not discovered as an opaque error at execution time.
- A control whose parent is unresolved renders disabled with its reason. It does not render enabled and fail on click.
- An unknown value renders visibly blocked rather than silently defaulting.
- Pending data renders loading. Load and failure paths ship **with** the change, never after it.

## Consumer enumeration

- Changing a contract on one side — schema, field catalog, type normalizer, matcher, write chain — means **enumerating that contract's consumers and aligning them in the same change**.
- If a consumer cannot be aligned yet, the gap renders as a visible operator-facing state. Never an exception, never a silent omission.

## Failure granularity

- A **row-level** problem blocks that row. Only a **call-level** problem may fail the call.
- One unmappable cell must never abort a batch of otherwise-valid rows.

## Preview / execute parity

- A dry run must not show one request set while a different one is sent.
- Validation that applies only on the live path breaks parity. Enforce at the layer both paths traverse — and be precise about *where*: a schema-level check that runs before the dry-run short-circuit will reject a legitimate preview that has no execution artifacts yet.
