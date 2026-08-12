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

# I2: a null spec ("superpowers": null) on the SUCCESS path must not crash.
# `spec = wanted[name] or {}` guarded the per-companion loop but not the
# OK-summary line, so a healthy, satisfied repo got an AttributeError instead
# of a clean pass — a gate firing wrongly on the success path (A8-shaped, and
# worse: it fires when everything is actually fine).
writestate '{"version":"1.22.2","files":{},"companions":{"superpowers":null}}'; writereg "$REG_OK"
run; check "null spec, satisfied declaration, still passes" 0 $?

# I2: a non-dict, non-null spec is a malformed declaration, not a spec that's
# merely missing optional fields — it must die() loudly via the established
# convention, not crash on a bare .get() deeper in.
writestate '{"version":"1.22.2","files":{},"companions":{"superpowers":"latest"}}'; writereg "$REG_OK"
run; check "non-dict spec dies instead of crashing" 1 $?
out=$( cd "$T" && CLAUDE_PLUGIN_REGISTRY="$T/registry.json" python3 "$KIT/scripts/check_companions.py" 2>&1; true )
printf '%s' "$out" | grep -q "check_companions: ERROR:"; check "non-dict spec uses the die() convention" 0 $?

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
python3 -c "import json,sys; s=json.load(open('$T/.claude/.framework-state.json')); sys.exit(0 if s.get('companions',{}).get('superpowers') and s.get('version')=='1.22.2' else 1)"
check "upgrade preserves companions and version after save_state" 0 $?

# I3: save_state must not silently drop a key it doesn't know the name of —
# that is the same failure class this branch just fixed for `companions`
# specifically (enumerating known keys closes one instance; this closes the
# class). A future key added to .framework-state.json must survive an upgrade
# even though save_state was never taught its name.
writestate '{"version":"1.0.0","files":{},"some_future_key":{"kept":true}}'
( cd "$T" && python3 - "$KIT" <<'PY' >/dev/null 2>&1
import sys, os
sys.path.insert(0, os.path.join(sys.argv[1], "scripts"))
import upgrade
state = upgrade.load_state(".")
upgrade.save_state(".", "1.22.2", state.get("files", {}))
PY
)
python3 -c "import json,sys; s=json.load(open('$T/.claude/.framework-state.json')); sys.exit(0 if s.get('some_future_key',{}).get('kept') is True and s.get('version')=='1.22.2' else 1)"
check "save_state preserves an unrelated/unknown key across an upgrade" 0 $?

# C1: the scaffolder writes a companions-only state file at step 7 of
# project-init, before the framework baseline exists (step 11 runs
# `upgrade.py --apply` for the first time). upgrade.py must survive reading
# that file — not crash on state['version'] / state["files"] before classify()
# even runs — and must come out the other side with a real baseline recorded.
writestate '{"companions":{"superpowers":{"min_version":"6.2.0"}}}'
( cd "$T" && python3 "$KIT/scripts/upgrade.py" --plugin "$KIT" --apply >/dev/null 2>&1 )
check "upgrade.py --apply survives a companions-only state file (C1)" 0 $?
python3 -c "import json,sys; s=json.load(open('$T/.claude/.framework-state.json')); sys.exit(0 if s.get('companions',{}).get('superpowers',{}).get('min_version')=='6.2.0' and s.get('version') else 1)"
check "C1: companions-only recovery still records a real baseline" 0 $?

# I1: drive main() itself (not save_state directly) so the call site at
# upgrade.py's `save_state(base, newver, files, registry_ids, companions=...)`
# is actually exercised. A harness that only calls save_state directly cannot
# see a regression at that call site — which is exactly what happened once:
# the keyword was dropped there and this harness still reported fail=0. Uses
# the kit itself as the plugin under upgrade, the same shape verified to exit
# 0 by hand.
writestate '{"version":"1.0.0","files":{},"companions":{"superpowers":{"min_version":"6.2.0"}}}'
( cd "$T" && python3 "$KIT/scripts/upgrade.py" --plugin "$KIT" --apply >/dev/null 2>&1 )
check "upgrade.py --apply (main) exits 0 against the kit as plugin (I1)" 0 $?
python3 -c "import json,sys; s=json.load(open('$T/.claude/.framework-state.json')); sys.exit(0 if s.get('companions',{}).get('superpowers',{}).get('min_version')=='6.2.0' else 1)"
check "I1: main()'s real call site still carries companions through" 0 $?

rm -rf "$T"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
