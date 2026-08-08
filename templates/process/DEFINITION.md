# Definition of Ready / Definition of Done

Two checklists. Both are binary — a partial yes is a no.

## Definition of Ready (spec may leave Stage 1)

- [ ] The problem is stated in terms of who is blocked and by what — not in terms of the proposed solution
- [ ] Success is observable. Someone outside the work could tell whether it happened.
- [ ] Scope has an explicit **Not doing** list
- [ ] Every external system it touches is named, with read/write/both noted
- [ ] Data model changes are sketched, including what becomes canonical
- [ ] Failure modes are listed: what happens when a dependency is down, slow, or lying
- [ ] Any expensive-to-reverse choice has an ADR, or is explicitly deferred with a note
- [ ] Someone other than the author has read it and disagreed with at least one thing, or confirmed they had nothing to push back on

If a spec passes this without a single question raised, it is usually underspecified rather than perfect.

## Definition of Done (PR may leave Stage 4)

- [ ] Verify passes: typecheck, lint, tests, contract check
- [ ] New behavior has a test that fails without the change
- [ ] Bugs have a regression test reproducing the original report
- [ ] Authorization is enforced and tested on every new route
- [ ] Errors use the standard envelope; no internal detail leaks to a client
- [ ] Logs carry a correlation ID and no payloads, credentials, or PII
- [ ] External calls have timeouts and bounded retries
- [ ] Migrations are reversible, or documented as not, with a stated plan
- [ ] Generated types regenerated; nothing hand-edited
- [ ] `.env.example` updated for any new configuration
- [ ] Docs updated where behavior changed — CLAUDE.md, README, or the relevant rule
- [ ] Rollback step written in the PR description
- [ ] Seed data still loads from a clean reset

## Guard hygiene — applies to every check added

- [ ] Every new guard has been **broken deliberately, seen to fail, and restored**. A guard that passed on its first run has proved nothing.
- [ ] Every test that iterates a collection asserts the collection is **non-empty** first
- [ ] No load-bearing number is trusted from a single source — cross-checked against a second
- [ ] If a fixture was corrected, confirmed that no case it previously expressed was deleted
- [ ] Anything that genuinely cannot be guarded is **named**, with what would catch it later. Silence reads as "guarded."

## Contract changes

- [ ] Every consumer of the changed contract enumerated and aligned **in this change**
- [ ] Any consumer that could not be aligned renders a visible operator-facing state — never an exception, never silence
- [ ] Preview and execute produce the same request set
- [ ] No new value, type, or shape degrades to a default; unknowns fail a check or render blocked

## Statelessness — when the project runs more than one instance

- [ ] No new module-level mutable state, in-process lock, scheduler, or rate limiter
- [ ] Nothing written to local disk survives the request that wrote it
- [ ] Any new write path is idempotent, or carries an idempotency key
- [ ] Tested against the **two-instance** stack, not a single instance
- [ ] If the change adds cross-request state, a cross-instance test covers it: write on A, read on B

## The escape hatch

You may ship without meeting the Definition of Done exactly once per incident, and only for an incident. When you do, open the follow-up issue in the same hour, linked from the PR. An unpaid exception becomes a permanent lowering of the bar.
