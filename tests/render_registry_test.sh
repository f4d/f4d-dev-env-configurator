#!/usr/bin/env bash
# Red-then-green harness for scripts/render_registry.py (A2).
# Same contract as hooks_test.sh: every guard is seen to fail before it counts,
# and every cannot-evaluate path blocks rather than allows (G-02, G-03).
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

check() { # name, expected_exit, actual_exit
  if [ "$2" -eq "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (expected exit $2, got $3)"; fi
}

# Fixture plugin with a miniature registry in the real format.
mkdir -p "$TMP/plugin/templates/rules" "$TMP/proj/.claude/rules"
cat > "$TMP/plugin/templates/rules/REGISTRY.md" <<'EOF'
# Rule Registry

## Core

| ID | Rule | Should be | Today | Promote when |
|---|---|---|---|---|
| C-01 | Never commit secrets | HOOK | **HOOK** | done |
| C-06 | Conventional commits | LINT | PROSE | commitlint |

## Money

| ID | Rule | Should be | Today | Promote when |
|---|---|---|---|---|
| M-01 | Integer cents only | TEST | PROSE | conservation test |
EOF
R() { python3 "$KIT/scripts/render_registry.py" --plugin "$TMP/plugin" "$@"; }
M="$TMP/proj/.claude/rules/manifest.json"

# 1. GREEN: valid manifest renders exactly the held rows.
echo '{"rules":["C-01","C-06"],"overrides":{"C-06":"LINT"}}' > "$M"
out="$(R --manifest "$M")"; check "valid manifest renders" 0 $?
echo "$out" | grep -q "C-01" && echo "$out" | grep -q "C-06" || { fail=$((fail+1)); echo "FAIL: held rows missing"; }
echo "$out" | grep -q "M-01" && { fail=$((fail+1)); echo "FAIL: unheld row rendered"; } || true
echo "$out" | grep -q "LINT \*(project override)\*" || { fail=$((fail+1)); echo "FAIL: override not applied"; }
echo "$out" | grep -q "## Money" && { fail=$((fail+1)); echo "FAIL: empty section rendered"; } || true

# 2. RED: unknown ID in rules blocks.
echo '{"rules":["C-01","Z-99"]}' > "$M"; R --manifest "$M" --validate >/dev/null 2>&1; check "unknown ID blocks" 2 $?
# 3. RED: override on unheld rule blocks.
echo '{"rules":["C-01"],"overrides":{"M-01":"TEST"}}' > "$M"; R --manifest "$M" --validate >/dev/null 2>&1; check "override on unheld rule blocks" 2 $?
# 4. RED: empty rules list blocks (vacuous-render guard, S-01 applied to the tool).
echo '{"rules":[]}' > "$M"; R --manifest "$M" --validate >/dev/null 2>&1; check "empty rules blocks" 2 $?
# 5. RED: unknown manifest key blocks (a typo'd key must not be silently ignored).
echo '{"rules":["C-01"],"overides":{}}' > "$M"; R --manifest "$M" --validate >/dev/null 2>&1; check "unknown key blocks" 2 $?
# 6. RED fail-loud: manifest missing.
R --manifest "$TMP/nope.json" --validate >/dev/null 2>&1; check "missing manifest blocks" 2 $?
# 7. RED fail-loud: manifest unparseable.
echo '{not json' > "$M"; R --manifest "$M" --validate >/dev/null 2>&1; check "unparseable manifest blocks" 2 $?
# 8. RED fail-loud: plugin registry missing.
echo '{"rules":["C-01"]}' > "$M"; python3 "$KIT/scripts/render_registry.py" --plugin "$TMP/empty" --manifest "$M" --validate >/dev/null 2>&1; check "missing registry blocks" 2 $?
# 9. RED fail-loud: duplicate ID in the registry itself blocks (A9 uniqueness).
printf '\n| C-01 | Duplicate | HOOK | HOOK | done |\n' >> "$TMP/plugin/templates/rules/REGISTRY.md"
R --manifest "$M" --validate >/dev/null 2>&1; check "duplicate registry ID blocks" 2 $?
# 10. RED: duplicate ID in manifest blocks.
cat > "$TMP/plugin/templates/rules/REGISTRY.md" <<'EOF'
## Core

| ID | Rule | Should be | Today | Promote when |
|---|---|---|---|---|
| C-01 | Never commit secrets | HOOK | **HOOK** | done |
EOF
echo '{"rules":["C-01","C-01"]}' > "$M"; R --manifest "$M" --validate >/dev/null 2>&1; check "duplicate manifest ID blocks" 2 $?
# 11. GREEN: --validate on the KIT'S OWN full registry with a real module manifest.
echo '{"rules":["C-01","C-02","C-03","C-04","C-05","C-06","C-07","C-08"]}' > "$M"
python3 "$KIT/scripts/render_registry.py" --plugin "$KIT" --manifest "$M" --validate >/dev/null 2>&1; check "kit registry validates" 0 $?

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
