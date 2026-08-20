---
id: guards
always_apply: true
---
# Guards, Not Memos

A rule written in prose is advisory and will eventually be ignored. A rule
expressed as a hook or a test executes. Classify accordingly.

## Guard hygiene — non-negotiable

- **A guard that passes on its first run has proved nothing.** Break the code deliberately, confirm the guard fails, restore. Only then is it a guard.
- The same applies to a whole harness: a scaffold nobody has watched fail is not a scaffold, it is decoration.
- If something genuinely cannot be guarded, **say so explicitly and name what would catch it later.** Silence reads as "guarded."

## Where a rule belongs

| The failure | Belongs in |
|---|---|
| Expensive or irreversible if it happens once | A hook. Exit 2. |
| Detectable from the code or its output | A test |
| Requires judgment about intent or design | A skill, or human review |
| None of the above | Prose — and accept it will sometimes be ignored |

If you are relying on a prose rule to prevent something expensive, it is
mis-classified. Say so rather than restating it more firmly.

## Test discipline

- Red first. A test that has never failed has not been shown to test anything.
- Improving a fake can delete coverage. When a fixture is corrected, check that no model or case it previously expressed has quietly disappeared.
- Assert the collection is non-empty before asserting anything about its contents.
