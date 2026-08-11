# A4/A5 acceptance run — 2026-08-11

The kill/re-run protocol from BACKLOG A4/A5, executed against kit v1.16.0 in a
scratch repo (session scratchpad, deleted after). Every phase's raw output is
in the evidence log below.

| Criterion | Result |
|---|---|
| A5: `--plan` prints the plan and writes nothing | **MET** — repo contained only `.git` after the plan; persistence offered and declined |
| A4-1: kill after Round 2 → resume at Round 3, nothing re-asked | **MET** — Step 0 schema check passed, summary shown, interview resumed at Round 3 |
| A4-2: kill mid-scaffold → resume completes without duplicating | **MET** — 6 pre-kill files byte-identical (SHA-verified) after resume; 13 remaining written; 19 total |
| Commit-step re-entry (1.13.1 regression) | **MET** — `phases.scaffold_commit` recorded; re-entry skips |
| Delete-on-success only | **Exercised against the runnable subset** — state survived both kills; deleted only after the subset passed. Full-Step-4 deletion discipline (a real failing verify must keep the state) is owed in O4 |
| P-04: plan matches execution | **MET over the exercised subset** — predeclared plan file-list vs `git ls-files`: identical. Reviewed 2026-08-11: the subset omitted spec-mandated outputs (verify/gates/preflight workflows, issue templates, guard test templates, PR template, `.framework-state.json` baseline), so full-spec parity is owed in O4 |
| A2 manifest in a scaffold | first live exercise — 22-rule manifest written and validated against the plugin registry |

## Honest bounds

- Executed by one agent in one session, simulating kills as hard stops at the
  specified points and resumes as cold re-entries reading only the state file.
  A fresh-session interactive run remains the gold proof — this run proves the
  spec is executable and its resume semantics are coherent, not that a
  different operator cannot misread it.
- Step 4 ran its runnable subset for a no-dependency throwaway (`node --test`
  green, commit check, manifest validation). Full verify-on-rich-scaffold
  across module combinations is O4's scope (conformance suite).

## Evidence log (verbatim)

```
=== PHASE A: /project-init --plan (A5 zero-write proof) ===
Interview held in memory. Answers: org=RoofAdvisor(profile found) project=kit-acceptance throwaway ts-only frontend=none db=none multi-instance=no integrations=none inbound=none standalone not-live. Modules: core guards silent-degradation. Skipped: all conditional.
--- plan printed (files + side effects) — now asserting ZERO writes:
git status: []
.claude exists: no
.git
persistence offered, DECLINED (per 1.13.1 spec)
--- PLAN (predeclared in Phase A, for P-04 parity check in Phase G) ---
FILES: .gitignore CLAUDE.md .claude/rules/org.md .claude/rules/core.md .claude/rules/guards.md .claude/rules/silent-degradation.md .claude/rules/manifest.json .claude/settings.json package.json docs/decisions/001-stack.md docs/decisions/002-single-instance.md docs/log.md docs/intake.md docs/LIFECYCLE.md docs/DEFINITION.md docs/ENFORCEMENT.md docs/TEST_STRATEGY.md tests/hooks_test.sh README.md
SIDE EFFECTS: scaffold commit; upgrade.py --apply baseline record; SINGLE_INSTANCE repo variable SKIPPED (no GitHub remote — plan states this explicitly); no stack start (db=none); no host toolchain mutation (node already present, no corepack needed for a no-dep scaffold)
=== PHASE B: real run, Rounds 0-2, state persisted per spec, then KILL ===
state after Round 2 (KILL POINT 1):
  round: 2 | answers: 16 | written: 0
SESSION KILLED.
=== PHASE C: RESUME 1 (fresh entry at Step 0) ===
Step 0: state found. schema check: complete (1.14.2 fields present)
Step 0 summary shown to user: mode=NEW, rounds completed=2, 16 answers, 0 files written
User chose: RESUME.
-> Resuming at Round 3. Rounds 0-2 NOT re-asked (A4 done-when criterion 1: MET)
Round 3 walked: storage? not mentioned->skip. multi-instance? no->skip both. money/chain/multi-source/frontend/production/PII? none apply. Round 3 complete, zero questions.
Step 2 plan table shown; user approved. Recording confirmed plan:
  state: round=4, decided_modules=['core', 'guards', 'silent-degradation']
=== PHASE D: Step 3 begins — preexisting captured at execution start; 6 writes; KILL ===
preexisting captured at first entry into Step 3: [] (empty dir — NEW mode)
6 files written and recorded. SHA snapshot taken (for no-duplication proof):
  e833fca96448  .gitignore
  aeacb1301eb5  CLAUDE.md
  662197e96d9f  .claude/rules/org.md
  b055ced529e6  .claude/rules/core.md
  3969f71df22e  .claude/rules/guards.md
  59b5e4d3935d  .claude/rules/silent-degradation.md
SESSION KILLED MID-SCAFFOLD (KILL POINT 2).
=== PHASE E: RESUME 2 (fresh Step 0) — complete without duplicating ===
Step 0: state found, schema complete. round=4 (plan confirmed) -> skip interview entirely.
written_files has 6 entries -> resume scaffold, skipping exactly those.
No-duplication proof: all 6 phase-D files byte-identical after resume: PASS
remaining 13 files written; written_files now 19
phases.scaffold_commit recorded = True (A4 done-when criterion 2: MET — completed without duplicating)
=== PHASE F: runnable Step-4 subset + delete-on-success ===
scaffold commit: 50858bd chore: project scaffold via f4d-kit
# todo 0
# duration_ms 7.64325
render_registry: OK — 22 rules, 0 overrides, all IDs resolve.
re-entry check: phases.scaffold_commit=True -> commit step would SKIP (no 'nothing to commit' failure).
Step-4 checks passed -> state file DELETED. exists now: False
git status after delete: [] (.init-state.json was gitignored — never staged)
=== PHASE G: P-04 parity — plan vs executed ===
plan-vs-executed diff: IDENTICAL — P-04 parity MET
```
