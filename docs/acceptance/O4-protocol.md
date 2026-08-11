# O4 tier 2 — behavioral conformance protocol (agent-run)

Tier 1 (`tests/conformance_test.sh`) proves the templates compose mechanically.
Tier 2 proves scaffolds behave — it needs an agent following `/project-init`,
not bash, and it owns the two debts bounded out of the 2026-08-11 A4/A5
acceptance run:

For each module combination worth exercising (minimum: throwaway-minimal,
single-instance + db, multi-instance + db, storage + determinism, money):

1. **Full-spec scaffold** in a scratch repo — every output the skill mandates,
   including workflows, issue templates, guard test templates, gate scripts,
   PR template, and the `upgrade.py --apply` baseline.
2. **Plan/execute parity, full-spec** — `--plan` first; the predeclared file
   list AND side-effect list must match what execution then does, completely.
3. **Verify green on the empty scaffold** — the generated verify command runs
   and passes with real toolchains (`corepack`/`uv` host mutations are part of
   this tier and must appear in the plan first).
4. **Failing-verify keeps state** — break the scaffold deliberately, run
   Step 4, confirm verification fails AND `.claude/.init-state.json` survives;
   fix, re-run, confirm it passes and only then deletes.
5. **Record the run** as a dated artifact in `docs/acceptance/`, bounds stated.

One rich combo per kit minor release is the cadence; all five combos before
v2.0. Runs are cheap to script for an agent and worthless to fake — every step
produces evidence (file lists, state snapshots, exit codes) that goes in the
artifact verbatim.
