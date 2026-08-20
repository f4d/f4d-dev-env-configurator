#!/usr/bin/env bash
# Red-then-green harness for scripts/render_instructions.py (spec 001, cap 2).
# Same contract as render_registry_test.sh: every failure path is seen to exit 2
# before it counts, and every cannot-evaluate path blocks rather than passes.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${RI_SCRIPT:-$KIT/scripts/render_instructions.py}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
check() { if [ "$2" -eq "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (expected exit $2, got $3)"; fi; }

RULES="$TMP/.claude/rules"; mkdir -p "$RULES"
mod() { printf -- '---\nid: %s\nalways_apply: %s\n---\n# %s\n- rule.\n' "$1" "$2" "$3" > "$RULES/$1.md"; }
mod core true  "Core"
mod guards true "Guards"
mod api  false "API"
mod money false "Money"
printf '# Rule Registry\nnot a module\n' > "$RULES/REGISTRY.md"
R() { python3 "$SCRIPT" --rules-dir "$RULES" --root "$TMP" "$@"; }

R --validate >/dev/null 2>&1; check "valid frontmatter validates" 0 $?
R --write --targets CLAUDE.md,AGENTS.md >/dev/null 2>&1; check "write succeeds" 0 $?
R --check --targets CLAUDE.md,AGENTS.md >/dev/null 2>&1; check "check clean after write" 0 $?

grep -q '`core`' "$TMP/CLAUDE.md" && grep -q '`guards`' "$TMP/CLAUDE.md" || { fail=$((fail+1)); echo "FAIL: always modules missing"; }
grep -q '`api`' "$TMP/CLAUDE.md" || { fail=$((fail+1)); echo "FAIL: on-demand module missing"; }
grep -q 'REGISTRY' "$TMP/CLAUDE.md" && { fail=$((fail+1)); echo "FAIL: REGISTRY rendered"; } || true
al=$(grep -n '`core`'  "$TMP/CLAUDE.md" | head -1 | cut -d: -f1)
ad=$(grep -n '`api`'   "$TMP/CLAUDE.md" | head -1 | cut -d: -f1)
[ "$al" -lt "$ad" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: always not ordered before on-demand"; }

python3 - "$TMP/CLAUDE.md" <<'PY'
import sys; p=sys.argv[1]; t=open(p).read().replace('`api`','`TAMPERED`'); open(p,'w').write(t)
PY
R --check --targets CLAUDE.md >/dev/null 2>&1; check "hand-edit inside block is drift" 2 $?

printf '\n\nHUMAN NOTE outside the block.\n' >> "$TMP/CLAUDE.md"
R --write --targets CLAUDE.md >/dev/null 2>&1
grep -q 'HUMAN NOTE outside the block.' "$TMP/CLAUDE.md" || { fail=$((fail+1)); echo "FAIL: content outside block lost"; }
R --check --targets CLAUDE.md >/dev/null 2>&1; check "check clean after re-write" 0 $?

R --check --targets CLAUDE.md,GEMINI.md >/dev/null 2>&1; check "missing target file is drift" 2 $?

printf -- '---\nalways_apply: true\n---\n# Bad\n' > "$RULES/bad.md"
R --validate >/dev/null 2>&1; check "missing id blocks" 2 $?
rm "$RULES/bad.md"

printf -- '---\nid: bad\nalways_apply: yes\n---\n# Bad\n' > "$RULES/bad.md"
R --validate >/dev/null 2>&1; check "non-boolean always_apply blocks" 2 $?
rm "$RULES/bad.md"

mod dupe false "Dupe A"; printf -- '---\nid: dupe\nalways_apply: false\n---\n# Dupe B\n' > "$RULES/dupe2.md"
R --validate >/dev/null 2>&1; check "duplicate id blocks" 2 $?
rm "$RULES/dupe.md" "$RULES/dupe2.md"

EMPTY="$TMP/empty/.claude/rules"; mkdir -p "$EMPTY"
python3 "$SCRIPT" --rules-dir "$EMPTY" --validate >/dev/null 2>&1; check "empty rules dir blocks" 2 $?

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
