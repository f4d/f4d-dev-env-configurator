#!/usr/bin/env bash
# Red-then-green harness for check_companions.py (CP-01).
# Same contract as the other harnesses: every branch is seen to fail before it
# counts, and the cannot-evaluate path blocks rather than allows (G-03).
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() { if [ "$2" -eq "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (expected exit $2, got $3)"; fi }

T="$(mktemp -d)"; ( cd "$T" && git init -q ); mkdir -p "$T/.claude"

writestate() { printf '%s' "$1" > "$T/.claude/.framework-state.json"; }
writereg()   { printf '%s' "$1" > "$T/registry.json"; }
run() { ( cd "$T" && CLAUDE_PLUGIN_REGISTRY="$T/registry.json" python3 "$KIT/scripts/check_companions.py" >/dev/null 2>&1 ); }

REG_OK='{"version":2,"plugins":{"superpowers@claude-plugins-official":[{"version":"6.2.0"}]}}'
REG_OLD='{"version":2,"plugins":{"superpowers@claude-plugins-official":[{"version":"5.9.0"}]}}'
REG_NONE='{"version":2,"plugins":{}}'

# GREEN: no declaration at all — nothing to verify.
writestate '{"version":"1.22.2","files":{}}'; writereg "$REG_OK"
run; check "no companions declared passes" 0 $?

# RED: declared, host has it but too old.
writestate '{"version":"1.22.2","files":{},"companions":{"superpowers":{"min_version":"6.2.0"}}}'
writereg "$REG_OLD"
run; check "red: installed version below min blocks" 1 $?

# GREEN: same declaration, host satisfies it.
writereg "$REG_OK"
run; check "green: satisfied declaration passes" 0 $?

# RED: declared, host does not have it at all.
writereg "$REG_NONE"
run; check "red: missing companion blocks" 1 $?

# SKIP: no host registry — CI. Not applicable is not a violation.
( cd "$T" && CLAUDE_PLUGIN_REGISTRY="$T/does-not-exist.json" python3 "$KIT/scripts/check_companions.py" >/dev/null 2>&1 )
check "skip: absent host registry is not a violation" 0 $?

# FAIL-LOUD (G-03): malformed state cannot be evaluated, so it blocks.
writestate '{"version":"1.22.2","companions":'; writereg "$REG_OK"
run; check "fail-loud: malformed framework-state blocks" 1 $?

# Message names the companion and both versions, so the fix is obvious.
writestate '{"version":"1.22.2","files":{},"companions":{"superpowers":{"min_version":"6.2.0"}}}'
writereg "$REG_OLD"
out=$( cd "$T" && CLAUDE_PLUGIN_REGISTRY="$T/registry.json" python3 "$KIT/scripts/check_companions.py" 2>/dev/null; true )
printf '%s' "$out" | grep -q "superpowers"; check "message names the companion" 0 $?
printf '%s' "$out" | grep -q "5.9.0"; check "message names the installed version" 0 $?
printf '%s' "$out" | grep -q "6.2.0"; check "message names the required version" 0 $?

# An upgrade must not destroy the declaration. save_state rebuilds the payload
# from scratch, so an unknown key is dropped unless it is carried deliberately.
writestate '{"version":"1.0.0","files":{},"companions":{"superpowers":{"min_version":"6.2.0"}}}'
( cd "$T" && python3 - "$KIT" <<'PY' >/dev/null 2>&1
import sys, os
sys.path.insert(0, os.path.join(sys.argv[1], "scripts"))
import upgrade
state = upgrade.load_state(".")
upgrade.save_state(".", "1.22.2", state.get("files", {}), companions=state.get("companions"))
PY
)
python3 -c "import json,sys; sys.exit(0 if json.load(open('$T/.claude/.framework-state.json')).get('companions',{}).get('superpowers') else 1)"
check "upgrade preserves the companion declaration" 0 $?

rm -rf "$T"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
