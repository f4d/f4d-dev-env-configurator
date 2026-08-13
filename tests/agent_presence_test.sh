#!/usr/bin/env bash
# Red-then-green harness for check_agents.py (A20 / G-07).
# Same contract as the other harnesses: every branch is seen to fail before it
# counts, and the cannot-evaluate path blocks rather than allows (G-03).
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() { if [ "$2" -eq "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (expected exit $2, got $3)"; fi }

T="$(mktemp -d)"; ( cd "$T" && git init -q )
RULES="$T/.claude/rules"; AGENTS="$T/.claude/agents"; STATE="$T/.claude/.framework-state.json"
# reset() puts the repo in "adopted" state (framework-state.json present) by
# default, since that is what most cases below want to exercise; the two
# adoption-signal cases explicitly rm -f "$STATE" after calling it.
reset() { rm -rf "$RULES" "$AGENTS"; mkdir -p "$RULES" "$AGENTS"; printf '{}' > "$STATE"; }
run() { ( cd "$T" && python3 "$KIT/scripts/check_agents.py" >/dev/null 2>&1 ); }
out() { ( cd "$T" && python3 "$KIT/scripts/check_agents.py" 2>&1 ); }

# SKIP: repo with none of the kit's state at all — no .framework-state.json,
# no .claude/rules/ — has not adopted f4d-kit. Not a violation.
rm -rf "$RULES" "$AGENTS"; rm -f "$STATE"
run; check "no framework-state.json (or rules/) at all skips cleanly" 0 $?
out | grep -q "SKIP"; check "skip message says SKIP" 0 $?

# RED-then-green regression (review r3771422153, PR #34): a `.claude/rules/`
# directory's mere existence is not the adoption signal — Claude Code's own
# native rules feature can populate one on a repo that never touched f4d-kit.
# Before the fix this fell through to a full evaluation and reported the
# unconditional agent as falsely missing; the fix keys adoption off
# .claude/.framework-state.json instead, which this repo never wrote.
reset
rm -f "$STATE"
printf 'Prefer tabs over spaces in this repo.\n' > "$RULES/generic-house-style.md"
run; check "rules/ populated but no framework-state.json still skips" 0 $?
o=$(out); printf '%s' "$o" | grep -q "SKIP"; check "skip message says SKIP even though rules/ exists" 0 $?

# RED-then-green regression, found by actually running this script against
# f4d-kit's own repo post-merge (2026-08-13), not by inspection: this repo
# carries .claude/.framework-state.json (A18 self-opts it into its own
# plugin-declared hooks, unrelated to being a scaffolded consumer) but has no
# .claude/rules/ of its own — it is the plugin source, not a target. Before
# this fix, framework-state.json alone was treated as sufficient adoption
# signal, so this shape fell through to full evaluation and reported
# verify-runner.md falsely missing. The fix requires BOTH signals together.
reset
rm -rf "$RULES"
run; check "framework-state.json present but rules/ entirely absent still skips (f4d-kit's own shape)" 0 $?
o=$(out); printf '%s' "$o" | grep -q "SKIP"; check "skip message says SKIP for the framework-state-only shape" 0 $?

# G-03 fail-loud must survive the fix above: rules/ present as a plain FILE
# (corrupted) is a different state than rules/ absent entirely, and must
# still die() rather than be swallowed into the new SKIP path — the fix uses
# os.path.exists(rules_dir), not os.path.isdir(rules_dir), specifically to
# keep this distinction.
reset
rm -rf "$RULES"; printf 'not a directory' > "$RULES"
run; check "rules/ present as a plain file (corrupted) still fail-louds, not skips" 1 $?
o=$(out); printf '%s' "$o" | grep -qi "not a directory"; check "corrupted rules/ error names the problem" 0 $?

# GREEN: kit adopted, no conditional modules held, verify-runner present — the
# unconditional floor, nothing more required.
reset
printf 'x' > "$RULES/core.md"
printf 'agent' > "$AGENTS/verify-runner.md"
run; check "no conditional modules: verify-runner alone is enough" 0 $?

# RED: verify-runner.md itself missing — unconditional, so this blocks even
# with zero conditional modules held. The floor A20 exists to protect.
reset
printf 'x' > "$RULES/core.md"
run; check "red: verify-runner.md missing (unconditional) blocks" 1 $?
o=$(out); printf '%s' "$o" | grep -q "verify-runner.md: missing"; check "message names verify-runner.md" 0 $?
printf '%s' "$o" | grep -q "unconditional"; check "message explains: unconditional" 0 $?

# GREEN: verify-runner.md restored.
printf 'agent' > "$AGENTS/verify-runner.md"
run; check "green: verify-runner.md restored" 0 $?

# RED: database module held, schema-reviewer.md missing.
reset
printf 'agent' > "$AGENTS/verify-runner.md"
printf 'x' > "$RULES/database.md"
run; check "red: database held, schema-reviewer.md missing blocks" 1 $?
o=$(out); printf '%s' "$o" | grep -q "schema-reviewer.md: missing"; check "message names schema-reviewer.md" 0 $?
printf '%s' "$o" | grep -q "rules/database.md is held"; check "message cites database.md as the reason" 0 $?

# GREEN: schema-reviewer.md restored.
printf 'agent' > "$AGENTS/schema-reviewer.md"
run; check "green: schema-reviewer.md restored" 0 $?

# RED: data-integration module held, integration-auditor.md missing.
reset
printf 'agent' > "$AGENTS/verify-runner.md"
printf 'x' > "$RULES/data-integration.md"
run; check "red: data-integration held, integration-auditor.md missing blocks" 1 $?
o=$(out); printf '%s' "$o" | grep -q "integration-auditor.md: missing"; check "message names integration-auditor.md" 0 $?

# GREEN: integration-auditor.md restored.
printf 'agent' > "$AGENTS/integration-auditor.md"
run; check "green: integration-auditor.md restored" 0 $?

# RED: contracts module held, contract-drift-checker.md missing.
reset
printf 'agent' > "$AGENTS/verify-runner.md"
printf 'x' > "$RULES/contracts.md"
run; check "red: contracts held, contract-drift-checker.md missing blocks" 1 $?
o=$(out); printf '%s' "$o" | grep -q "contract-drift-checker.md: missing"; check "message names contract-drift-checker.md" 0 $?

# GREEN: contract-drift-checker.md restored.
printf 'agent' > "$AGENTS/contract-drift-checker.md"
run; check "green: contract-drift-checker.md restored" 0 $?

# GREEN: a module NOT held does not require its agent — the check must not
# over-require. Only database is held; integration-auditor and
# contract-drift-checker are correctly never expected.
reset
printf 'agent' > "$AGENTS/verify-runner.md"
printf 'x' > "$RULES/database.md"
printf 'agent' > "$AGENTS/schema-reviewer.md"
run; check "green: unheld modules do not require their agent" 0 $?

# RED: a present-but-empty file counts as missing — a zero-byte agent file has
# no instructions to run and is exactly as broken as an absent one.
printf '' > "$AGENTS/schema-reviewer.md"
run; check "red: empty agent file blocks" 1 $?
o=$(out); printf '%s' "$o" | grep -q "schema-reviewer.md: empty"; check "message distinguishes empty from missing" 0 $?

# GREEN: non-empty content clears it.
printf 'agent' > "$AGENTS/schema-reviewer.md"
run; check "green: non-empty content clears the empty-file violation" 0 $?

# RED-then-green regression (review r3771422162, PR #34): a directory
# standing in for an agent file must not read as present. os.listdir() lists
# a directory's name exactly like a file's, and os.path.getsize() on a
# directory is normally nonzero — before the fix this passed both the
# presence and empty-file checks and printed OK while there was no usable
# agent definition at all.
reset
printf 'x' > "$RULES/core.md"
mkdir -p "$AGENTS/verify-runner.md"
run; check "red: a directory standing in for verify-runner.md blocks" 1 $?
o=$(out); printf '%s' "$o" | grep -q "verify-runner.md: a directory, not a file"; check "message distinguishes directory from empty/missing" 0 $?

# GREEN: replacing the directory with a real file clears it.
rm -rf "$AGENTS/verify-runner.md"
printf 'agent' > "$AGENTS/verify-runner.md"
run; check "green: real file in place of the directory clears the violation" 0 $?

# FAIL-LOUD (G-03): .claude/rules exists but is a file, not a directory —
# cannot evaluate what modules are held, so this must block, not skip.
rm -rf "$RULES"; printf 'not a directory' > "$RULES"
run; check "fail-loud: .claude/rules as a plain file blocks" 1 $?
o=$(out); printf '%s' "$o" | grep -q "check_agents: ERROR:"; check "fail-loud uses the die() convention" 0 $?
rm -f "$RULES"; mkdir -p "$RULES"

# FAIL-LOUD (G-03): .claude/agents exists but is a file, not a directory.
printf 'x' > "$RULES/core.md"
rm -rf "$AGENTS"; printf 'not a directory' > "$AGENTS"
run; check "fail-loud: .claude/agents as a plain file blocks" 1 $?
o=$(out); printf '%s' "$o" | grep -q "check_agents: ERROR:"; check "fail-loud (agents) uses the die() convention" 0 $?
rm -f "$AGENTS"; mkdir -p "$AGENTS"

rm -rf "$T"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
