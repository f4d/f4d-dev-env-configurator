#!/usr/bin/env bash
# Red-then-green harness for f4d-kit hooks.
# A guard that has never been seen to fail is not a guard.
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/../hooks" && pwd)"
KIT_LOG_PATH="$(cd "$HOOKS/.." && pwd)/.claude/.enforcement-log"
KIT_LOG_BEFORE="$(cat "$KIT_LOG_PATH" 2>/dev/null | cksum)"
pass=0; fail=0

# A18 — every hook below is now declared globally via hooks/hooks.json and
# gates itself on .claude/.framework-state.json (hook_opted_in, hooks/_parse.sh).
# Every fixture that exercises a hook's REAL logic must therefore opt in, or
# every case degenerates into testing the gate instead of the rule. mkstate
# writes the minimal marker — presence is the whole signal; content is never
# read (see hook_opted_in's own comment), so a minimal object is exactly as
# "opted in" as a fully-populated one.
mkstate() { mkdir -p "$1/.claude" && printf '{"version":"test","files":{}}' > "$1/.claude/.framework-state.json"; }

tmp=$(mktemp -d); ( cd "$tmp" && git init -q && touch report.ts && git add -A ); mkstate "$tmp"

check() { # name expected_exit hook json [dir]
  # Runs inside the disposable fixture repo — a denying case must write its
  # telemetry THERE, never into the kit's own .claude/.enforcement-log, or
  # every test run corrupts the fire counts /retro reads. dir defaults to the
  # shared opted-in fixture; the A18 section below passes a non-opted-in one.
  local name="$1" want="$2" hook="$3" json="$4" dir="${5:-$tmp}" got
  echo "$json" | (cd "$dir" && bash "$HOOKS/$hook") >/dev/null 2>&1; got=$?
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
dc=$(mktemp -d); ( cd "$dc" && git init -q && git config user.email t@t && git config user.name t && echo "x" > a.py && git add -A && git commit -qm init && echo "y" >> a.py ); mkstate "$dc"
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

dc2=$(mktemp -d); ( cd "$dc2" && git init -q && git config user.email t@t && git config user.name t && echo "# doc" > README.md && git add -A && git commit -qm init && echo "more" >> README.md ); mkstate "$dc2"
( cd "$dc2" && bash "$HOOKS/done-check.sh" >/dev/null 2>&1 ); got=$?
if [ "$got" -eq 0 ]; then echo "  PASS  ignores docs-only changes"; pass=$((pass+1))
else echo "  FAIL  ignores docs-only changes (got $got)"; fail=$((fail+1)); fi

echo "verify-record.sh"
vr=$(mktemp -d); ( cd "$vr" && git init -q ); mkstate "$vr"
echo '{"tool_input":{"command":"pnpm verify"}}' | (cd "$vr" && bash "$HOOKS/verify-record.sh" >/dev/null 2>&1)
if [ -f "$vr/.claude/.last-verify" ]; then echo "  PASS  records a verify run"; pass=$((pass+1))
else echo "  FAIL  records a verify run"; fail=$((fail+1)); fi

vr2=$(mktemp -d); ( cd "$vr2" && git init -q ); mkstate "$vr2"
echo '{"tool_input":{"command":"ls -la"}}' | (cd "$vr2" && bash "$HOOKS/verify-record.sh" >/dev/null 2>&1)
if [ ! -f "$vr2/.claude/.last-verify" ]; then echo "  PASS  ignores unrelated commands"; pass=$((pass+1))
else echo "  FAIL  ignores unrelated commands"; fail=$((fail+1)); fi

echo "format.sh"
# Self-contained fixture rather than relying on the ambient cwd: format.sh now
# gates on hook_opted_in too (A18), so it needs its own opted-in repo the same
# as every other hook, not whatever directory happened to invoke this suite.
fm=$(mktemp -d); ( cd "$fm" && git init -q ); mkstate "$fm"
if (cd "$fm" && echo '{"tool_input":{"file_path":"/nonexistent/x.py"}}' | CLAUDE_FILE_PATHS="/nonexistent/x.py" bash "$HOOKS/format.sh") >/dev/null 2>&1; then
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
et=$(mktemp -d); ( cd "$et" && git init -q ); mkstate "$et"
echo '{"tool_input":{"command":"git push --force origin main"}}' | (cd "$et" && bash "$HOOKS/guard.sh" >/dev/null 2>&1)
line=$( [ -f "$et/.claude/.enforcement-log" ] && tail -1 "$et/.claude/.enforcement-log" || echo "" )
if printf '%s' "$line" | awk -F'\t' 'NF==3 && $2=="C-02" {exit 0} {exit 1}'; then
  echo "  PASS  deny logs TSV with rule id (C-02)"; pass=$((pass+1))
else echo "  FAIL  deny logs TSV with rule id (got: $line)"; fail=$((fail+1)); fi

# 2. HARD PROPERTY: an unwritable log must never weaken the deny. chmod 555 is
#    NOT this test: root bypasses Unix permission bits entirely, and this
#    suite's own CI (like many people's local Docker setups) commonly runs as
#    root, so a fixture that relies on permission bits alone silently stops
#    testing anything the moment it runs there — reproduced directly: the same
#    write that 555 blocks for a normal user goes through fine once permission
#    bits stop being the obstacle (root's whole nature), and a regression
#    where a telemetry failure suppresses the deny would sail through
#    undetected in exactly that environment while this fixture kept reporting
#    green. Pre-create .enforcement-log AS A DIRECTORY instead: opening a
#    directory for writing fails with EISDIR — a type check the kernel makes
#    on the open() call itself, independent of any uid/permission-bit check,
#    per open(2): "[EISDIR] The named file is a directory, and the arguments
#    specify that it is to be opened for writing." Verified empirically too:
#    the write still fails this way even with the directory chmod 777 — the
#    permission bits root effectively sees, since root ignores them — so this
#    blocks root exactly as it blocks everyone else. .claude itself stays a
#    normal writable directory holding the opt-in marker, so this fixture
#    still exercises "write fails", not "not opted in".
et2=$(mktemp -d); ( cd "$et2" && git init -q ); mkstate "$et2"; mkdir -p "$et2/.claude/.enforcement-log"
echo '{"tool_input":{"file_path":"/x/.env"}}' | (cd "$et2" && bash "$HOOKS/guard.sh" >/dev/null 2>&1); got=$?
if [ "$got" -eq 2 ]; then echo "  PASS  deny still exits 2 when telemetry cannot write"; pass=$((pass+1))
else echo "  FAIL  telemetry failure weakened the deny (got $got)"; fail=$((fail+1)); fi
# The exit code alone doesn't prove the write actually failed — a SUCCESSFUL
# write produces the same exit 2 (see check 1 above), which is exactly how the
# old fixture went blind under root without ever going red. Assert the write's
# outcome directly: log_deny only ever appends text to this path and nothing
# else touches it, so if the write had gone through it could not still be an
# empty directory.
if [ -d "$et2/.claude/.enforcement-log" ] && [ -z "$(ls -A "$et2/.claude/.enforcement-log" 2>/dev/null)" ]; then
  echo "  PASS  telemetry write actually failed (path is still an empty directory)"; pass=$((pass+1))
else echo "  FAIL  telemetry write succeeded despite the fixture (EISDIR mechanism regressed)"; fail=$((fail+1)); fi

# 3. An allowed command writes nothing.
et3=$(mktemp -d); ( cd "$et3" && git init -q ); mkstate "$et3"
echo '{"tool_input":{"command":"pnpm test"}}' | (cd "$et3" && bash "$HOOKS/guard.sh" >/dev/null 2>&1)
if [ ! -f "$et3/.claude/.enforcement-log" ]; then echo "  PASS  allow writes no telemetry"; pass=$((pass+1))
else echo "  FAIL  allow wrote telemetry"; fail=$((fail+1)); fi

# 4. rule-zero denies log C-05.
et4=$(mktemp -d); ( cd "$et4" && git init -q && touch report.ts && git add -A ); mkstate "$et4"
echo "{\"tool_input\":{\"file_path\":\"$et4/reportV2.ts\"}}" | (cd "$et4" && bash "$HOOKS/rule-zero.sh" >/dev/null 2>&1)
if [ -f "$et4/.claude/.enforcement-log" ] && tail -1 "$et4/.claude/.enforcement-log" | grep -q "	C-05	"; then
  echo "  PASS  rule-zero deny logs C-05"; pass=$((pass+1))
else echo "  FAIL  rule-zero deny logs C-05"; fail=$((fail+1)); fi

# 5. Fail-closed: a secret-class deny (C-01) withholds the detail entirely —
#    assignments, redirect payloads, and URL-embedded keys alike.
et5=$(mktemp -d); ( cd "$et5" && git init -q ); mkstate "$et5"
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

echo "A18 — global opt-in gate (hook_opted_in, hooks/_parse.sh)"
# Every hook above is declared globally via hooks/hooks.json (see hooks/hooks.json
# and docs/BACKLOG.md A18), so each one now matches on EVERY repo the user has
# Claude Code open in — not only ones this kit scaffolded. These cases are the
# fail-loud/fail-safe pair non-negotiable #2 calls for: absent state must
# disable cleanly, cheaply, and BEFORE stdin is even read; malformed-but-PRESENT
# state must not become a way to defeat enforcement by corrupting the marker
# instead of removing it.

ni=$(mktemp -d); ( cd "$ni" && git init -q && touch report.ts && git add -A )   # NEVER opted in — no .claude/.framework-state.json at all

check "guard.sh: silent on a non-opted-in repo (would otherwise block .env)"     0 guard.sh     '{"tool_input":{"file_path":"/x/.env"}}'              "$ni"
check "rule-zero.sh: silent on a non-opted-in repo (would otherwise block V2)"   0 rule-zero.sh "{\"tool_input\":{\"file_path\":\"$ni/reportV2.ts\"}}" "$ni"

# guard.sh's own "FAILS LOUD on garbage" path (tested above, opted in) must NOT
# fire here — proof the gate runs BEFORE stdin is ever parsed, which is what
# makes it cheap and safe to run unconditionally on every repo the user opens.
check "guard.sh: does not even parse stdin on a non-opted-in repo (garbage in)"      0 guard.sh 'not json at all'      "$ni"
check "guard.sh: does not even parse stdin on a non-opted-in repo (empty tool_input)" 0 guard.sh '{"tool_input":{}}'   "$ni"

if [ ! -f "$ni/.claude/.enforcement-log" ]; then echo "  PASS  no telemetry written for a non-opted-in repo"; pass=$((pass+1))
else echo "  FAIL  non-opted-in repo wrote telemetry"; fail=$((fail+1)); fi

echo '{"tool_input":{"command":"pnpm verify"}}' | (cd "$ni" && bash "$HOOKS/verify-record.sh" >/dev/null 2>&1)
if [ ! -f "$ni/.claude/.last-verify" ]; then echo "  PASS  verify-record.sh: silent on a non-opted-in repo"; pass=$((pass+1))
else echo "  FAIL  verify-record.sh wrote .last-verify on a non-opted-in repo"; fail=$((fail+1)); fi

sc_ni=$(cd "$ni" && bash "$HOOKS/session-context.sh" 2>&1)
if [ -z "$sc_ni" ]; then echo "  PASS  session-context.sh silent on a non-opted-in repo"; pass=$((pass+1))
else echo "  FAIL  session-context.sh emitted output on a non-opted-in repo: $sc_ni"; fail=$((fail+1)); fi
if [ ! -f "$ni/.claude/.session-log" ]; then echo "  PASS  session-context.sh writes no telemetry for a non-opted-in repo"; pass=$((pass+1))
else echo "  FAIL  session-context.sh wrote telemetry for a non-opted-in repo"; fail=$((fail+1)); fi

( cd "$ni" && bash "$HOOKS/format.sh" >/dev/null 2>&1 ); got=$?
if [ "$got" -eq 0 ]; then echo "  PASS  format.sh silent on a non-opted-in repo"; pass=$((pass+1))
else echo "  FAIL  format.sh on a non-opted-in repo (got $got)"; fail=$((fail+1)); fi

# done-check.sh: the exact fixture shape that blocks when opted in (see
# "done-check.sh" section above) must NOT block here — same rule, opt-in is
# the only variable.
ni2=$(mktemp -d); ( cd "$ni2" && git init -q && git config user.email t@t && git config user.name t && echo "x" > a.py && git add -A && git commit -qm init && echo "y" >> a.py )
( cd "$ni2" && bash "$HOOKS/done-check.sh" >/dev/null 2>&1 ); got=$?
if [ "$got" -eq 0 ]; then echo "  PASS  done-check.sh silent on a non-opted-in repo"; pass=$((pass+1))
else echo "  FAIL  done-check.sh on a non-opted-in repo (got $got)"; fail=$((fail+1)); fi

# Outside any git repo at all, with a payload that WOULD block if evaluated —
# must still be instant, silent, and not crash. (Empty stdin would pass this
# for the wrong reason: guard.sh already no-ops on an empty command, before
# and after A18, so that alone would not distinguish the gate from a coincidence.)
nogit=$(mktemp -d)
echo '{"tool_input":{"file_path":"/x/.env"}}' | (cd "$nogit" && bash "$HOOKS/guard.sh") >/dev/null 2>&1; got=$?
if [ "$got" -eq 0 ]; then echo "  PASS  guard.sh silent outside any git repo (payload would otherwise block)"; pass=$((pass+1))
else echo "  FAIL  guard.sh outside any git repo (got $got)"; fail=$((fail+1)); fi

# Presence beats content: a corrupted-but-PRESENT state file must still count
# as opted in. hook_opted_in only ever calls `[ -f ]` on it — parsing it and
# failing open on a parse error would turn "corrupt the marker" into a way to
# silently disable enforcement, exactly the class of bug A18 exists to close,
# one level up.
mal=$(mktemp -d); ( cd "$mal" && git init -q && mkdir -p .claude && printf 'not json at all {' > .claude/.framework-state.json )
check "guard.sh: malformed-but-present state still counts as opted in (still blocks)" 2 guard.sh '{"tool_input":{"file_path":"/x/.env"}}' "$mal"
if [ -f "$mal/.claude/.enforcement-log" ] && tail -1 "$mal/.claude/.enforcement-log" | grep -q "	C-01	"; then
  echo "  PASS  malformed-state repo still logs the C-01 deny"; pass=$((pass+1))
else echo "  FAIL  malformed-state repo did not log the deny"; fail=$((fail+1)); fi

# 7. The harness must leave the kit's own enforcement log EXACTLY as it found
#    it — which may legitimately exist with real local denies (it is
#    persistent and gitignored). Compare, don't require absence.
if [ "$(cat "$KIT_LOG_PATH" 2>/dev/null | cksum)" = "$KIT_LOG_BEFORE" ]; then
  echo "  PASS  kit's own enforcement log unchanged by the test run"; pass=$((pass+1))
else echo "  FAIL  tests modified the kit's real enforcement log"; fail=$((fail+1)); fi

rm -rf "$tmp" "$dc" "$dc2" "$vr" "$vr2" "$et" "$et2" "$et3" "$et4" "$et5" "$fm" "$ni" "$ni2" "$nogit" "$mal"
echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] || exit 1
