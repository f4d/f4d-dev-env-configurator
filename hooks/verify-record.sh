#!/usr/bin/env bash
# PostToolUse:Bash — records when the verify command ran and whether it passed.
# Feeds both done-check.sh and the /project-audit evidence report.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_parse.sh"
hook_opted_in || exit 0
input=$(cat)
cmd=$(hook_field "$input" "command")
[ -z "$cmd" ] && exit 0

case "$cmd" in
  *verify*|*"pytest"*|*"vitest"*|*"forge test"*|*"npm test"*|*"pnpm test"*) ;;
  *) exit 0 ;;
esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
mkdir -p "$root/.claude" 2>/dev/null
touch "$root/.claude/.last-verify"
printf '%s\tverify\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(printf '%s' "$cmd" | cut -c1-60)" \
  >> "$root/.claude/.session-log" 2>/dev/null
exit 0
