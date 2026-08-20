#!/usr/bin/env bash
# Red-then-green harness for scripts/render_instructions.py (spec 001, cap 2).
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
# org.md: the per-repo org constraints block — no frontmatter, must be SKIPPED
# (scaffolded repos always have it; treating it as a module broke every scaffold).
printf '# Org constraints\n- company rule.\n' > "$RULES/org.md"
R() { python3 "$SCRIPT" --rules-dir "$RULES" --root "$TMP" "$@"; }

R --validate >/dev/null 2>&1; check "org.md/REGISTRY skipped, rest validate" 0 $?
R --write --targets CLAUDE.md,AGENTS.md >/dev/null 2>&1; check "write succeeds" 0 $?
R --check --targets CLAUDE.md,AGENTS.md >/dev/null 2>&1; check "check clean after write" 0 $?

grep -q '`core`' "$TMP/CLAUDE.md" && grep -q '`api`' "$TMP/CLAUDE.md" || { fail=$((fail+1)); echo "FAIL: modules missing"; }
grep -qiE 'REGISTRY|Org constraints' "$TMP/CLAUDE.md" && { fail=$((fail+1)); echo "FAIL: non-module rendered"; } || true
al=$(grep -n '`core`' "$TMP/CLAUDE.md" | head -1 | cut -d: -f1); ad=$(grep -n '`api`' "$TMP/CLAUDE.md" | head -1 | cut -d: -f1)
[ "$al" -lt "$ad" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: order"; }

# drift: in-block hand edit
python3 - "$TMP/CLAUDE.md" <<'PY'
import sys; p=sys.argv[1]; open(p,'w').write(open(p).read().replace('`api`','`TAMPERED`'))
PY
R --check --targets CLAUDE.md >/dev/null 2>&1; check "in-block edit is drift" 2 $?

# heal + preserve outside content
printf '\n\nHUMAN NOTE.\n' >> "$TMP/CLAUDE.md"
R --write --targets CLAUDE.md >/dev/null 2>&1
grep -q 'HUMAN NOTE.' "$TMP/CLAUDE.md" || { fail=$((fail+1)); echo "FAIL: outside content lost"; }
R --check --targets CLAUDE.md >/dev/null 2>&1; check "clean after re-write" 0 $?

# {{RULES_INDEX}} token (scaffold path): a tmpl-style file gets the block, no leftover token
printf '# Proj\n## Rules\n{{RULES_INDEX}}\n## Non-negotiables\n- x\n' > "$TMP/TMPL.md"
R --write --targets TMPL.md >/dev/null 2>&1; check "token file writes" 0 $?
grep -q '{{RULES_INDEX}}' "$TMP/TMPL.md" && { fail=$((fail+1)); echo "FAIL: token left behind"; } || true
grep -q 'f4d-kit:rules' "$TMP/TMPL.md" || { fail=$((fail+1)); echo "FAIL: block not inserted at token"; }
R --check --targets TMPL.md >/dev/null 2>&1; check "token file clean after write" 0 $?
# an UNrendered token is drift, not a pass
printf '## Rules\n{{RULES_INDEX}}\n' > "$TMP/TOK2.md"
R --check --targets TOK2.md >/dev/null 2>&1; check "unrendered token is drift" 2 $?

# multiple managed blocks (bad merge): --check fails, --write collapses to one
cp "$TMP/CLAUDE.md" "$TMP/DUP.md"; python3 - "$TMP/DUP.md" "$SCRIPT" "$RULES" "$TMP" <<'PY'
import sys, subprocess, re
p=sys.argv[1]
b=subprocess.run(["python3",sys.argv[2],"--rules-dir",sys.argv[3],"--root",sys.argv[4],"--targets","x","--check"],capture_output=True) # noqa (ignore)
t=open(p).read()
m=re.search(r"<!-- BEGIN f4d-kit:rules.*?<!-- END f4d-kit:rules -->", t, re.DOTALL).group(0)
open(p,'w').write(t + "\n\n" + m + "\n")   # a second identical block
PY
n=$(grep -c 'BEGIN f4d-kit:rules' "$TMP/DUP.md"); [ "$n" -eq 2 ] || { fail=$((fail+1)); echo "FAIL: fixture didn't duplicate ($n)"; }
R --check --targets DUP.md >/dev/null 2>&1; check "two blocks is drift" 2 $?
R --write --targets DUP.md >/dev/null 2>&1
n2=$(grep -c 'BEGIN f4d-kit:rules' "$TMP/DUP.md"); [ "$n2" -eq 1 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: not collapsed to one ($n2)"; }
R --check --targets DUP.md >/dev/null 2>&1; check "clean after collapse" 0 $?

# missing target is drift
R --check --targets CLAUDE.md,GEMINI.md >/dev/null 2>&1; check "missing target is drift" 2 $?

# fail-loud on bad frontmatter
printf -- '---\nalways_apply: true\n---\n# Bad\n' > "$RULES/bad.md"; R --validate >/dev/null 2>&1; check "missing id blocks" 2 $?; rm "$RULES/bad.md"
printf -- '---\nid: bad\nalways_apply: yes\n---\n# Bad\n' > "$RULES/bad.md"; R --validate >/dev/null 2>&1; check "non-bool always_apply blocks" 2 $?; rm "$RULES/bad.md"
mod dupe false "Dupe A"; printf -- '---\nid: dupe\nalways_apply: false\n---\n# Dupe B\n' > "$RULES/dupe2.md"
R --validate >/dev/null 2>&1; check "duplicate id blocks" 2 $?; rm "$RULES/dupe.md" "$RULES/dupe2.md"
EMPTY="$TMP/empty/.claude/rules"; mkdir -p "$EMPTY"; python3 "$SCRIPT" --rules-dir "$EMPTY" --validate >/dev/null 2>&1; check "empty rules dir blocks" 2 $?

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
