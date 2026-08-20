# 004 — A MANUAL/attestation registry tier for accuracy-critical paths

- **Status:** Accepted
- **Date:** 2026-08-20

## Context

The registry's status vocabulary answers one question for every rule: *what
stops this from being ignored?* Today the answers are `HOOK`, `TEST`, `GATE`,
`AGENT`, `LINT`, `PROSE`, and `JUDGMENT`. Every enforced tier assumes a machine
can decide the rule: a hook greps the payload, a test asserts an invariant, a
gate reads the diff. `JUDGMENT` is the honest label for a rule where mechanising
it would produce false positives — but `JUDGMENT` is explicitly **not enforced**;
it is a finished, advisory state.

There is a class of rule that fits none of these: a path where correctness is
real and consequential but **no automated check can prove it**, and a human must
look and sign off on each change. RoofAdvisor has these now — a money
calculation whose correctness depends on domain facts a test cannot encode, a
known-vulnerable integration surface, a regulated output. Marking such a path
`JUDGMENT` says "we thought about it once" and enforces nothing on the next
change; marking it `TEST`/`GATE` claims a machine proof that does not exist and
will be quietly weakened until it is green-and-wrong. The gap is a tier whose
enforcement mechanism is *a recorded human attestation*, not a re-run of a check.

This is capability 4 of spec 001 ("Domain rulebook + MANUAL tier") and it adds a
row to a vocabulary many repos will come to depend on, so it gets an ADR before
it is built.

## Decision

We add a `MANUAL` status tier: a rule enforced by the **presence of a signed
human attestation, committed to the repo, naming the path and the basis for
sign-off**, required whenever a diff touches a path the repo has declared
MANUAL. `check_attestation.py` is the gate. **The attestation must be added or updated in
the same diff that changes the MANUAL path** — it carries a change identifier (the
path plus the commit/PR it attests), so a stale prior attestation cannot satisfy a
later change to the same path. Storage is **tiered**: a committed `attestations/`
file for paths the repo declares audit-critical (regulated, needs a durable trail),
and a PR-body `## Attestation` for lightweight MANUAL paths — the lightweight case
spec 001 already accepts. The repo's MANUAL declaration says which tier each path
uses.

## Alternatives considered

| Option | Why not |
|---|---|
| Reuse `JUDGMENT` | `JUDGMENT` means "correctly not enforced." Overloading it to sometimes-require-a-signoff destroys the one distinction the registry exists to keep: enforced vs not. A reader could no longer trust that `JUDGMENT` means advisory. |
| A `HOOK` or `TEST` | The defining property of these paths is that **no automated check can prove correctness**. A hook/test here is theatre — it asserts something weaker than the real rule and licenses "green" on a wrong change. |
| PR-body attestation *as the only tier* | The PR body is not in the tree — not auditable after a squash-merge, not diffable, invisible to a later reader. So it is **retained for lightweight paths but insufficient for audit-critical ones**, which need a durable committed record; the tier is per declared path (see Decision). |
| Required GitHub reviewer / CODEOWNERS | GitHub-only, not offline-validatable, and leaves no per-path record of *what was attested* — only that someone clicked approve. Ownership review is a separate, complementary control (capability 5), not this one. |
| Nothing — leave it `PROSE` | `PROSE` on a mechanisable rule is tracked debt with a promote-when trigger; here there is nothing to promote *to*, so it would be permanent unenforced debt on exactly the paths that most need a gate. |

## Consequences

**Accepted costs.** A human gate can be rubber-stamped — `MANUAL` buys a recorded,
attributable decision, not a guarantee of care. We mitigate the worst failure the
way `check_rollback` does: the attestation must name the changed path and the
basis for sign-off, and a boilerplate or mismatched attestation (one that names a
different path, or claims "revert the commit" on an irreversible change) is
rejected rather than accepted. `MANUAL` also adds a per-repo declaration surface
(which paths are MANUAL) that the audit must keep honest, and one more gate in CI.

**Reversal cost.** Moderate-to-high, which is the reason for this record. Once
repos declare MANUAL paths and commit attestations against them, removing the
tier means unwiring `check_attestation.py`, migrating those declarations to some
other control, and deciding what happens to the committed attestation history —
a coordinated change across every adopting repo, not a one-file revert. Adding
the tier is cheap; removing it is not. (This is exactly the reversibility concern
tracked as A26 — a MANUAL tier is a capability whose adopt-out must be
consumer-aware.)

**Revisit when.** A later mechanism makes one of these paths genuinely
machine-checkable (then that path promotes MANUAL → TEST/GATE, the normal
promote-when flow), or if attestations prove to be uniformly rubber-stamped in
practice, in which case the honest move is to admit the control is not working
rather than keep the ceremony.
