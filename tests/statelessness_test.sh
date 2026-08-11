#!/usr/bin/env bash
# Red-then-green harness for check_statelessness.py — A13 boundary cases.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() { if [ "$2" -eq "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (expected exit $2, got $3)"; fi }

T="$(mktemp -d)"; ( cd "$T" && git init -q )
# RED: an unannotated module-level registry declaration fails — the scanner
# cannot see cross-file call timing, so unannotated means flagged, always.
echo 'const registry: Record<string, C> = {};' > "$T/reg.ts"
( cd "$T" && python3 "$KIT/scripts/check_statelessness.py" >/dev/null 2>&1 ); check "ST-01 red: unannotated registry blocks" 1 $?
# GREEN: the sanctioned import-time annotation clears it.
echo 'const registry: Record<string, C> = {}; // stateless-ok import-time registration — all registerX call sites are module top level' > "$T/reg.ts"
( cd "$T" && python3 "$KIT/scripts/check_statelessness.py" >/dev/null 2>&1 ); check "ST-01 green: import-time annotation passes" 0 $?
# RED: the annotation is line-scoped — another ST rule in the same file still fires.
printf 'const registry = {}; // stateless-ok import-time registration — reviewed\nconst limiter = new Map();\n' > "$T/reg.ts"
echo 'const rateLimit = {};' > "$T/other.ts"
( cd "$T" && python3 "$KIT/scripts/check_statelessness.py" >/dev/null 2>&1 ); check "no blanket allow: other findings still block" 1 $?
# GREEN: message points at the doctrine section. (Capture first: the scanner
# exits 1 on findings, and pipefail would mask grep's success through a pipe.)
rm "$T/other.ts"; echo 'const sessions = new Map();' > "$T/reg.ts"
out=$( cd "$T" && python3 "$KIT/scripts/check_statelessness.py" 2>/dev/null; true )
printf '%s' "$out" | grep -q "Import-time registries"; check "finding message cites the doctrine section" 0 $?
rm -rf "$T"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
