#!/usr/bin/env bash
# Red-then-green harness for f4d-kit hooks.
# A guard that has never been seen to fail is not a guard.
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/../hooks" && pwd)"
pass=0; fail=0

check() { # name expected_exit hook json
  local name="$1" want="$2" hook="$3" json="$4" got
  echo "$json" | bash "$HOOKS/$hook" >/dev/null 2>&1; got=$?
  if [ "$got" -eq "$want" ]; then echo "  PASS  $name"; pass=$((pass+1))
  else echo "  FAIL  $name (want exit $want, got $got)"; fail=$((fail+1)); fi
}

tmp=$(mktemp -d); ( cd "$tmp" && git init -q && touch report.ts && git add -A )

echo "guard.sh"
check "blocks .env"            2 guard.sh '{"tool_input":{"file_path":"/x/.env"}}'
check "blocks keystore"        2 guard.sh '{"tool_input":{"file_path":"/x/keystore/a"}}'
check "blocks force push"      2 guard.sh '{"tool_input":{"command":"git push --force origin main"}}'
check "blocks mainnet rpc"     2 guard.sh '{"tool_input":{"command":"cast send --rpc-url https://polygon-rpc.com"}}'
check "blocks DROP DATABASE"   2 guard.sh '{"tool_input":{"command":"psql -c \"DROP DATABASE app\""}}'
check "blocks --broadcast"     2 guard.sh '{"tool_input":{"command":"forge script X --broadcast"}}'
check "allows normal command"  0 guard.sh '{"tool_input":{"command":"pnpm test"}}'
check "FAILS LOUD on garbage"  2 guard.sh 'not json at all'

echo "rule-zero.sh"
check "blocks V2 variant"      2 rule-zero.sh "{\"tool_input\":{\"file_path\":\"$tmp/reportV2.ts\"}}"
check "blocks -final variant"  2 rule-zero.sh "{\"tool_input\":{\"file_path\":\"$tmp/report-final.ts\"}}"
check "blocks new- prefix"     2 rule-zero.sh "{\"tool_input\":{\"file_path\":\"$tmp/new-report.ts\"}}"
check "allows novel concept"   0 rule-zero.sh "{\"tool_input\":{\"file_path\":\"$tmp/invoices.ts\"}}"
check "allows existing file"   0 rule-zero.sh "{\"tool_input\":{\"file_path\":\"$tmp/report.ts\"}}"
check "FAILS LOUD on garbage"  2 rule-zero.sh 'not json at all'

echo "session-context.sh"
# G-02: the load-path fix is the most load-bearing hook in the system and had no test.
sc_out=$(cd "$tmp" && bash "$HOOKS/session-context.sh" 2>&1)
if printf '%s' "$sc_out" | grep -q "PROJECT RULES"; then
  echo "  PASS  emits rules banner"; pass=$((pass+1))
else echo "  FAIL  emits rules banner"; fail=$((fail+1)); fi

mkdir -p "$tmp/sub/deep"
sub_out=$(cd "$tmp/sub/deep" && bash "$HOOKS/session-context.sh" 2>&1)
if printf '%s' "$sub_out" | grep -q "did not start at the repo root"; then
  echo "  PASS  warns when cwd is not repo root"; pass=$((pass+1))
else echo "  FAIL  warns when cwd is not repo root"; fail=$((fail+1)); fi

if [ -f "$tmp/.claude/.session-log" ] && [ "$(wc -l < "$tmp/.claude/.session-log")" -ge 2 ]; then
  echo "  PASS  writes telemetry for every session"; pass=$((pass+1))
else echo "  FAIL  writes telemetry for every session"; fail=$((fail+1)); fi

if (cd /tmp && bash "$HOOKS/session-context.sh" >/dev/null 2>&1); then
  echo "  PASS  exits 0 outside any git repo"; pass=$((pass+1))
else echo "  FAIL  exits 0 outside any git repo"; fail=$((fail+1)); fi

echo "done-check.sh"
dc=$(mktemp -d); ( cd "$dc" && git init -q && git config user.email t@t && git config user.name t && echo "x" > a.py && git add -A && git commit -qm init && echo "y" >> a.py )
( cd "$dc" && bash "$HOOKS/done-check.sh" >/dev/null 2>&1 ); got=$?
if [ "$got" -eq 2 ]; then echo "  PASS  blocks done with no verify record"; pass=$((pass+1))
else echo "  FAIL  blocks done with no verify record (got $got)"; fail=$((fail+1)); fi

mkdir -p "$dc/.claude" && touch "$dc/.claude/.last-verify"
( cd "$dc" && bash "$HOOKS/done-check.sh" >/dev/null 2>&1 ); got=$?
if [ "$got" -eq 0 ]; then echo "  PASS  allows done after verify"; pass=$((pass+1))
else echo "  FAIL  allows done after verify (got $got)"; fail=$((fail+1)); fi

dc2=$(mktemp -d); ( cd "$dc2" && git init -q && git config user.email t@t && git config user.name t && echo "# doc" > README.md && git add -A && git commit -qm init && echo "more" >> README.md )
( cd "$dc2" && bash "$HOOKS/done-check.sh" >/dev/null 2>&1 ); got=$?
if [ "$got" -eq 0 ]; then echo "  PASS  ignores docs-only changes"; pass=$((pass+1))
else echo "  FAIL  ignores docs-only changes (got $got)"; fail=$((fail+1)); fi

echo "verify-record.sh"
vr=$(mktemp -d); ( cd "$vr" && git init -q )
echo '{"tool_input":{"command":"pnpm verify"}}' | (cd "$vr" && bash "$HOOKS/verify-record.sh" >/dev/null 2>&1)
if [ -f "$vr/.claude/.last-verify" ]; then echo "  PASS  records a verify run"; pass=$((pass+1))
else echo "  FAIL  records a verify run"; fail=$((fail+1)); fi

vr2=$(mktemp -d); ( cd "$vr2" && git init -q )
echo '{"tool_input":{"command":"ls -la"}}' | (cd "$vr2" && bash "$HOOKS/verify-record.sh" >/dev/null 2>&1)
if [ ! -f "$vr2/.claude/.last-verify" ]; then echo "  PASS  ignores unrelated commands"; pass=$((pass+1))
else echo "  FAIL  ignores unrelated commands"; fail=$((fail+1)); fi

echo "format.sh"
if echo '{"tool_input":{"file_path":"/nonexistent/x.py"}}' | CLAUDE_FILE_PATHS="/nonexistent/x.py" bash "$HOOKS/format.sh" >/dev/null 2>&1; then
  echo "  PASS  never blocks, even on a missing file"; pass=$((pass+1))
else echo "  FAIL  format.sh must never block"; fail=$((fail+1)); fi

rm -rf "$tmp" "$dc" "$dc2" "$vr" "$vr2"
echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] || exit 1
