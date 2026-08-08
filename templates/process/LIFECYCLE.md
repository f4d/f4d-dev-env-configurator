# Lifecycle

The path every piece of work takes, from "someone wants a thing" to "it's live and we learned something." Six stages. Each has an artifact, an owner, and an exit condition.

Nothing skips a stage. Small work moves through stages in minutes; large work takes days. The stages don't change.

---

## Stage 0 — Intake

**Artifact:** an entry in `docs/intake.md` or an issue
**Exit:** classified as Bug / Chore / Feature / Question, and sized S / M / L

Everything enters here. The point is to prevent the two most expensive failure modes: building without a decision, and re-litigating a decision already made.

| Class | Next stage | Needs a spec? |
|---|---|---|
| Bug | → Build | No. Needs a failing test. |
| Chore | → Build | No. |
| Feature (S) | → Build | No, but needs a one-paragraph intent in the issue |
| Feature (M/L) | → Spec | Yes |
| Question | → answered and closed, or promoted to Feature | — |

Sizing is by *uncertainty*, not hours. If you can't describe the finished state in one sentence, it's not S.

---

## Stage 1 — Spec

**Artifact:** `docs/specs/NNN-<slug>.md`
**Owner:** whoever proposed it
**Exit:** the Definition of Ready is met

Use `/write-spec`. A spec exists to make the disagreement happen before the code, not after. If nobody disagrees with a spec, it was probably too vague to be useful.

Specs are numbered, never deleted, and marked `Superseded by NNN` rather than edited into a lie.

---

## Stage 2 — Decide

**Artifact:** `docs/decisions/NNN-<slug>.md` (ADR)
**Exit:** decision recorded with the alternatives that lost, and why

Only for choices that are **expensive to reverse**: a datastore, an auth model, a vendor, a canonical-record rule, a public API shape, a language boundary.

Not for: naming, file layout, library choices you could swap in an afternoon.

Use `/decision-record`. The value is not the decision — it's the alternatives. Six months from now the question is always "did we consider X?", and the ADR answers it in ten seconds.

---

## Stage 3 — Build

**Artifact:** a branch, then a PR
**Exit:** Definition of Done met, verify passes

- Branch: `<type>/<scope>-<desc>`
- Use `/new-module`, `/new-integration`, or `/contract-first` where they apply — they exist so build #10 looks like build #1
- Commit conventionally, run verify before every commit
- Keep the PR under ~400 lines of real change. If it grows past that, split it. A PR nobody can review is a PR nobody reviews.

---

## Stage 4 — Review

**Artifact:** PR approval
**Exit:** all review gates pass

Run the relevant audit agents before requesting human review — they're cheaper than a reviewer's attention:

| Change touches | Run |
|---|---|
| A migration | `schema-reviewer` |
| An external source | `integration-auditor` |
| A shared payload | `contract-drift-checker` |
| Anything | `verify-runner` |

Human review looks at what agents can't: is this the right thing, is the abstraction right, will the next person understand it.

---

## Stage 5 — Ship

**Artifact:** a merge, a version bump, a changelog entry
**Exit:** deployed, health check green, rollback step written down

Use `/ship-it`. The rollback step is written *before* merge, not discovered during an incident. If the answer is "revert the commit," confirm no migration ran — otherwise that's not a rollback.

---

## Stage 6 — Learn

**Artifact:** an entry in `docs/log.md`
**Exit:** either nothing changed, or a rule changed

Use `/retro` — on a cadence (monthly) and after anything that went wrong.

The output that matters: **something Claude or a human got wrong twice becomes a rule.** That's the entire mechanism by which this framework improves. A retro that produces no rule change and no removed rule was a retro about a good month, which is fine, but say so explicitly.

---

## Where things live

```
docs/
├── specs/         NNN-<slug>.md    what we decided to build
├── decisions/     NNN-<slug>.md    why we chose this way
├── intake.md                       the queue
└── log.md                          what we learned, dated
.claude/rules/                      what we do about it
CHANGELOG.md                        what shipped
```

Specs and decisions are append-only history. `.claude/rules/` is the living present. The rules directory should be small; the docs directory grows forever.
