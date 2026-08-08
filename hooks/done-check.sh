#!/usr/bin/env bash
# Stop hook — refuses a silent "done" on a session that changed code but never
# ran the test suite.
#
# Not a correctness proof. It catches the specific failure of claiming completion
# from reading the diff rather than from watching it pass.
set -uo pipefail
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

changed=$(git -C "$root" diff --name-only HEAD 2>/dev/null | grep -Ev '\.(md|txt|json|ya?ml)$' | head -1)
[ -z "$changed" ] && exit 0

marker="$root/.claude/.last-verify"
if [ ! -f "$marker" ]; then
  echo "No verify run recorded this session, but source files changed." >&2
  echo "Run the project verify command before reporting completion." >&2
  echo "A 'done' claim not backed by a passing run is a guess about the diff." >&2
  exit 2
fi

# Stale if the marker predates the newest source change.
newest=$(git -C "$root" diff --name-only HEAD 2>/dev/null | grep -Ev '\.(md|txt)$' \
  | while read -r f; do [ -f "$root/$f" ] && stat -c %Y "$root/$f"; done | sort -rn | head -1)
mtime=$(stat -c %Y "$marker" 2>/dev/null || echo 0)
if [ -n "$newest" ] && [ "$newest" -gt "$mtime" ]; then
  echo "Source changed after the last verify run. Re-run verify before claiming done." >&2
  exit 2
fi
exit 0
