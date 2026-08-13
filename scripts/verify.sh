#!/usr/bin/env bash
# The kit's single verify command.
#
# /project-audit demands one of every project it audits ("A single verify
# command exists; it is identical in CLAUDE.md, the script, and CI; it passes
# right now"). The kit had none — five harness invocations and a handful of gate
# scripts, listed in START_HERE.md and duplicated in two workflows, with nothing
# tying them together.
#
# That gap was not cosmetic. hooks/verify-record.sh records a verify run only
# when the command matches *verify*|*pytest*|*vitest*|*forge test*|*npm test*|
# *pnpm test*, and `bash tests/hooks_test.sh` matches none of them. So the kit
# could never record a verify run against itself, and hooks/done-check.sh —
# which blocks Stop when source changed and no verify was recorded — would have
# blocked every single session here the moment the hooks were armed.
#
# Named `verify.sh` deliberately: it matches the *verify* pattern, so running it
# is what makes done-check.sh satisfiable in this repo.
#
# Exit 0 only when everything passes. Any failure is loud and fatal.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$KIT"

fail=0
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

section "harnesses"
total=0
for t in hooks render_registry gate_trio statelessness conformance companions scanner_agreement; do
  line=$(bash "tests/${t}_test.sh" 2>&1 | tail -1)
  n=$(printf '%s' "$line" | grep -o 'pass=[0-9]*' | cut -d= -f2)
  f=$(printf '%s' "$line" | grep -o 'fail=[0-9]*' | cut -d= -f2)
  # A harness that printed no counts did not run to completion — that is a
  # failure, not a zero. Absence reads as permission otherwise.
  if [ -z "${n:-}" ] || [ -z "${f:-}" ]; then
    printf '  %-20s NO COUNTS — harness did not complete\n' "$t"
    fail=1
    continue
  fi
  total=$((total + n))
  [ "$f" -eq 0 ] || fail=1
  printf '  %-20s %s\n' "$t" "$line"
done
printf '  %-20s %s assertions\n' "(total)" "$total"

section "gate scripts"
for g in check_statelessness check_guess_lists check_catch_empty check_log_hygiene \
         check_companions check_raw_sql check_pure_imports check_contract_pin \
         check_fixtures check_rollback; do
  if python3 "scripts/${g}.py" >/dev/null 2>&1; then
    printf '  %-24s clean\n' "$g"
  else
    printf '  %-24s FINDINGS\n' "$g"
    fail=1
  fi
done

# check_commits and check_test_count need BASE_REF and are meaningless without a
# base to compare against. CI supplies it; locally they are skipped, and the skip
# is printed rather than silent.
section "skipped locally (need BASE_REF — CI runs these)"
printf '  %-24s %s\n' "check_commits" "C-06"
printf '  %-24s %s\n' "check_test_count" "C-08"

section "result"
if [ "$fail" -eq 0 ]; then
  echo "  VERIFY PASSED"
else
  echo "  VERIFY FAILED"
fi
exit "$fail"
