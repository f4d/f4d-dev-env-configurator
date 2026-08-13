#!/usr/bin/env bash
# Red-then-green harness for check_agents.py (A20 / G-07).
# Same contract as the other harnesses: every branch is seen to fail before it
# counts, and the cannot-evaluate path blocks rather than allows (G-03).
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() { if [ "$2" -eq "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (expected exit $2, got $3)"; fi }

T="$(mktemp -d)"; ( cd "$T" && git init -q )
RULES="$T/.claude/rules"; AGENTS="$T/.claude/agents"
reset() { rm -rf "$RULES" "$AGENTS"; mkdir -p "$RULES" "$AGENTS"; }
run() { ( cd "$T" && python3 "$KIT/scripts/check_agents.py" >/dev/null 2>&1 ); }
out() { ( cd "$T" && python3 "$KIT/scripts/check_agents.py" 2>&1 ); }

# SKIP: repo with no .claude/rules/ at all has not adopted f4d-kit — not a violation.
rm -rf "$RULES" "$AGENTS"
run; check "no .claude/rules/ at all skips cleanly" 0 $?
out | grep -q "SKIP"; check "skip message says SKIP" 0 $?

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
