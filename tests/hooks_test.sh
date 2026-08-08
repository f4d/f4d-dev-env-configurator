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

rm -rf "$tmp"
echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] || exit 1
