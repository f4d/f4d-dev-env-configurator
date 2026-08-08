#!/usr/bin/env bash
# Stop hook — refuses a silent "done" on a session that changed code but never
# ran the test suite.
#
# Uses `git status --porcelain`, not `git diff HEAD`. The latter returns nothing
# in a repo with no commits, and misses untracked files entirely — so a brand new
# source file would not count as a change and the hook would pass silently.
# That is the exact failure class this framework exists to catch.
set -uo pipefail
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Every added/modified/untracked path, excluding docs and config.
changed=$(git -C "$root" status --porcelain 2>/dev/null \
  | sed 's/^...//' \
  | grep -Ev '\.(md|txt|json|ya?ml|lock)$' \
  | grep -Ev '^(docs|\.github|\.claude)/' \
  | head -20)
[ -z "$changed" ] && exit 0

marker="$root/.claude/.last-verify"
if [ ! -f "$marker" ]; then
  {
    echo "No verify run recorded this session, but source files changed:"
    printf '%s\n' "$changed" | head -5 | sed 's/^/  /'
    echo "Run the project verify command before reporting completion."
    echo "A 'done' claim not backed by a passing run is a guess about the diff."
  } >&2
  exit 2
fi

# Stale if any changed source file is newer than the last verify.
mtime=$(stat -c %Y "$marker" 2>/dev/null || echo 0)
newest=0
while IFS= read -r f; do
  [ -f "$root/$f" ] || continue
  t=$(stat -c %Y "$root/$f" 2>/dev/null || echo 0)
  [ "$t" -gt "$newest" ] && newest=$t
done <<< "$changed"

if [ "$newest" -gt "$mtime" ]; then
  echo "Source changed after the last verify run. Re-run verify before claiming done." >&2
  exit 2
fi
exit 0
