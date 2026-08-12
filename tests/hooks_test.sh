#!/usr/bin/env bash
# Red-then-green harness for f4d-kit hooks.
# A guard that has never been seen to fail is not a guard.
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/../hooks" && pwd)"
KIT_LOG_PATH="$(cd "$HOOKS/.." && pwd)/.claude/.enforcement-log"
KIT_LOG_BEFORE="$(cat "$KIT_LOG_PATH" 2>/dev/null | cksum)"
pass=0; fail=0

tmp=$(mktemp -d); ( cd "$tmp" && git init -q && touch report.ts && git add -A )

check() { # name expected_exit hook json
  # Runs inside the disposable fixture repo — a denying case must write its
  # telemetry THERE, never into the kit's own .claude/.enforcement-log, or
  # every test run corrupts the fire counts /retro reads.
  local name="$1" want="$2" hook="$3" json="$4" got
  echo "$json" | (cd "$tmp" && bash "$HOOKS/$hook") >/dev/null 2>&1; got=$?
  if [ "$got" -eq "$want" ]; then echo "  PASS  $name"; pass=$((pass+1))
  else echo "  FAIL  $name (want exit $want, got $got)"; fail=$((fail+1)); fi
}

echo "guard.sh"
check "blocks .env"            2 guard.sh '{"tool_input":{"file_path":"/x/.env"}}'
check "blocks keystore"        2 guard.sh '{"tool_input":{"file_path":"/x/keystore/a"}}'
check "blocks force push"      2 guard.sh '{"tool_input":{"command":"git push --force origin main"}}'
check "blocks mainnet rpc"     2 guard.sh '{"tool_input":{"command":"cast send --rpc-url https://polygon-rpc.com"}}'
check "blocks DROP DATABASE"   2 guard.sh '{"tool_input":{"command":"psql -c \"DROP DATABASE app\""}}'
check "blocks --broadcast"     2 guard.sh '{"tool_input":{"command":"forge script X --broadcast"}}'
check "allows normal command"  0 guard.sh '{"tool_input":{"command":"pnpm test"}}'
check "FAILS LOUD on garbage"  2 guard.sh 'not json at all'
check "blocks empty tool_input (schema drift)" 2 guard.sh '{"tool_input":{}}'
check "blocks truncated payload"               2 guard.sh '{"tool_input":oops'
check "blocks TERMINAL push -f"                2 guard.sh '{"tool_input":{"command":"git push -f"}}'

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

# A stale verify must block. This branch never fired on macOS: the mtime lookup
# used the GNU-only `stat -c %Y`, which BSD rejects outright, so both sides of
# the comparison fell back to 0 and `0 -gt 0` was always false. The guard
# reported success while evaluating nothing — verified against the pre-fix
# script, which exited 0 on exactly this scenario.
touch -t 202001010000 "$dc/.claude/.last-verify"
( cd "$dc" && bash "$HOOKS/done-check.sh" >/dev/null 2>&1 ); got=$?
if [ "$got" -eq 2 ]; then echo "  PASS  blocks done when the verify record is older than the change"; pass=$((pass+1))
else echo "  FAIL  blocks done when the verify record is older than the change (got $got)"; fail=$((fail+1)); fi

# ...and a fresh one must still pass, or the fix above would just block everything.
touch "$dc/.claude/.last-verify"
( cd "$dc" && bash "$HOOKS/done-check.sh" >/dev/null 2>&1 ); got=$?
if [ "$got" -eq 0 ]; then echo "  PASS  allows done when the verify record is newer than the change"; pass=$((pass+1))
else echo "  FAIL  allows done when the verify record is newer than the change (got $got)"; fail=$((fail+1)); fi

# G-03: no readable mtime means cannot-evaluate, which must block rather than
# allow. Shadow `stat` with a stub that always fails, leaving git and bash
# working — emptying PATH would only prove that bash cannot start.
statstub=$(mktemp -d); printf '#!/bin/sh\nexit 1\n' > "$statstub/stat"; chmod +x "$statstub/stat"
( cd "$dc" && PATH="$statstub:$PATH" bash "$HOOKS/done-check.sh" >/dev/null 2>&1 ); got=$?
if [ "$got" -eq 2 ]; then echo "  PASS  FAILS LOUD when no stat implementation works"; pass=$((pass+1))
else echo "  FAIL  FAILS LOUD when no stat implementation works (got $got)"; fail=$((fail+1)); fi
rm -rf "$statstub"

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

echo "guard-local.sh (A11 fallback — must work with the plugin GONE)"
GL="$(cd "$HOOKS/.." && pwd)/templates/scaffold/guard-local.sh"
gl=$(mktemp -d); ( cd "$gl" && git init -q )
echo '{"tool_input":{"file_path":"/x/.env"}}' | (cd "$gl" && bash "$GL") >/dev/null 2>&1; got=$?
if [ "$got" -eq 2 ]; then echo "  PASS  fallback blocks .env"; pass=$((pass+1)); else echo "  FAIL  fallback blocks .env (got $got)"; fail=$((fail+1)); fi
echo '{"tool_input":{"command":"git push --force origin main"}}' | (cd "$gl" && bash "$GL") >/dev/null 2>&1; got=$?
if [ "$got" -eq 2 ]; then echo "  PASS  fallback blocks force-push"; pass=$((pass+1)); else echo "  FAIL  fallback blocks force-push (got $got)"; fail=$((fail+1)); fi
echo '{"tool_input":{"command":"pnpm test"}}' | (cd "$gl" && bash "$GL") >/dev/null 2>&1; got=$?
if [ "$got" -eq 0 ]; then echo "  PASS  fallback allows normal command"; pass=$((pass+1)); else echo "  FAIL  fallback allows normal (got $got)"; fail=$((fail+1)); fi
echo 'not json at all' | (cd "$gl" && bash "$GL") >/dev/null 2>&1; got=$?
if [ "$got" -eq 2 ]; then echo "  PASS  fallback FAILS LOUD on garbage"; pass=$((pass+1)); else echo "  FAIL  fallback fail-loud (got $got)"; fail=$((fail+1)); fi
echo '{"tool_input":{}}' | (cd "$gl" && bash "$GL") >/dev/null 2>&1; got=$?
if [ "$got" -eq 2 ]; then echo "  PASS  fallback blocks empty tool_input"; pass=$((pass+1)); else echo "  FAIL  fallback empty tool_input (got $got)"; fail=$((fail+1)); fi
echo '{"tool_input":{"command":"git push -f"}}' | (cd "$gl" && bash "$GL") >/dev/null 2>&1; got=$?
if [ "$got" -eq 2 ]; then echo "  PASS  fallback blocks TERMINAL push -f"; pass=$((pass+1)); else echo "  FAIL  fallback terminal -f (got $got)"; fail=$((fail+1)); fi
rm -rf "$gl"

echo "enforcement telemetry (A10)"
# 1. A deny writes one TSV line tagged with its rule ID.
et=$(mktemp -d); ( cd "$et" && git init -q )
echo '{"tool_input":{"command":"git push --force origin main"}}' | (cd "$et" && bash "$HOOKS/guard.sh" >/dev/null 2>&1)
line=$( [ -f "$et/.claude/.enforcement-log" ] && tail -1 "$et/.claude/.enforcement-log" || echo "" )
if printf '%s' "$line" | awk -F'\t' 'NF==3 && $2=="C-02" {exit 0} {exit 1}'; then
  echo "  PASS  deny logs TSV with rule id (C-02)"; pass=$((pass+1))
else echo "  FAIL  deny logs TSV with rule id (got: $line)"; fail=$((fail+1)); fi

# 2. HARD PROPERTY: an unwritable log must never weaken the deny.
et2=$(mktemp -d); ( cd "$et2" && git init -q && touch .claude )   # .claude as a FILE — mkdir will fail
echo '{"tool_input":{"file_path":"/x/.env"}}' | (cd "$et2" && bash "$HOOKS/guard.sh" >/dev/null 2>&1); got=$?
if [ "$got" -eq 2 ]; then echo "  PASS  deny still exits 2 when telemetry cannot write"; pass=$((pass+1))
else echo "  FAIL  telemetry failure weakened the deny (got $got)"; fail=$((fail+1)); fi

# 3. An allowed command writes nothing.
et3=$(mktemp -d); ( cd "$et3" && git init -q )
echo '{"tool_input":{"command":"pnpm test"}}' | (cd "$et3" && bash "$HOOKS/guard.sh" >/dev/null 2>&1)
if [ ! -f "$et3/.claude/.enforcement-log" ]; then echo "  PASS  allow writes no telemetry"; pass=$((pass+1))
else echo "  FAIL  allow wrote telemetry"; fail=$((fail+1)); fi

# 4. rule-zero denies log C-05.
et4=$(mktemp -d); ( cd "$et4" && git init -q && touch report.ts && git add -A )
echo "{\"tool_input\":{\"file_path\":\"$et4/reportV2.ts\"}}" | (cd "$et4" && bash "$HOOKS/rule-zero.sh" >/dev/null 2>&1)
if [ -f "$et4/.claude/.enforcement-log" ] && tail -1 "$et4/.claude/.enforcement-log" | grep -q "	C-05	"; then
  echo "  PASS  rule-zero deny logs C-05"; pass=$((pass+1))
else echo "  FAIL  rule-zero deny logs C-05"; fail=$((fail+1)); fi

# 5. Fail-closed: a secret-class deny (C-01) withholds the detail entirely —
#    assignments, redirect payloads, and URL-embedded keys alike.
et5=$(mktemp -d); ( cd "$et5" && git init -q )
echo '{"tool_input":{"command":"deploy API_KEY=hunter2-super-secret --now"}}' | (cd "$et5" && bash "$HOOKS/guard.sh" >/dev/null 2>&1)
echo '{"tool_input":{"command":"printf sk-live-ABC123 > .env"}}' | (cd "$et5" && bash "$HOOKS/guard.sh" >/dev/null 2>&1)
loglines=$( [ -f "$et5/.claude/.enforcement-log" ] && cat "$et5/.claude/.enforcement-log" || echo "" )
if printf '%s' "$loglines" | grep -Eq "hunter2|sk-live-ABC123"; then
  echo "  FAIL  secret value leaked into telemetry"; fail=$((fail+1))
elif [ "$(printf '%s\n' "$loglines" | grep -c "withheld — secret-class deny")" -eq 2 ]; then
  echo "  PASS  secret-class denies withhold the detail entirely"; pass=$((pass+1))
else echo "  FAIL  withhold marker missing (log: $loglines)"; fail=$((fail+1)); fi

# 6. Non-secret-class denies keep a redacted detail (defense in depth).
#    (MY_PASSWORD= is redaction-regex material but NOT a C-01 pattern, so the
#    command routes to the force-push branch — C-02, non-withheld.)
echo '{"tool_input":{"command":"git push --force origin main MY_PASSWORD=abc123"}}' | (cd "$et5" && bash "$HOOKS/guard.sh" >/dev/null 2>&1)
last=$(tail -1 "$et5/.claude/.enforcement-log")
if printf '%s' "$last" | grep -q "abc123"; then
  echo "  FAIL  non-secret-class deny leaked an assignment value"; fail=$((fail+1))
elif printf '%s' "$last" | grep -q "C-02.*REDACTED"; then
  echo "  PASS  non-secret-class deny logs redacted detail"; pass=$((pass+1))
else echo "  FAIL  expected C-02 with REDACTED (got: $last)"; fail=$((fail+1)); fi

# 7. The harness must leave the kit's own enforcement log EXACTLY as it found
#    it — which may legitimately exist with real local denies (it is
#    persistent and gitignored). Compare, don't require absence.
if [ "$(cat "$KIT_LOG_PATH" 2>/dev/null | cksum)" = "$KIT_LOG_BEFORE" ]; then
  echo "  PASS  kit's own enforcement log unchanged by the test run"; pass=$((pass+1))
else echo "  FAIL  tests modified the kit's real enforcement log"; fail=$((fail+1)); fi

rm -rf "$tmp" "$dc" "$dc2" "$vr" "$vr2" "$et" "$et2" "$et3" "$et4" "$et5"
echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] || exit 1
