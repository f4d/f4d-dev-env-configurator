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

## The escape hatch

You may ship without meeting the Definition of Done exactly once per incident, and only for an incident. When you do, open the follow-up issue in the same hour, linked from the PR. An unpaid exception becomes a permanent lowering of the bar.
