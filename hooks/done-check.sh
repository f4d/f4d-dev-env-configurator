#!/usr/bin/env bash
# Stop hook — refuses a silent "done" on a session that changed code but never
# ran the test suite.
#
# Uses `git status --porcelain`, not `git diff HEAD`. The latter returns nothing
# in a repo with no commits, and misses untracked files entirely — so a brand new
# source file would not count as a change and the hook would pass silently.
# That is the exact failure class this framework exists to catch.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_parse.sh"
hook_opted_in || exit 0
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

# Modification time, portably. GNU coreutils takes -c %Y; BSD/macOS takes -f %m
# and rejects -c outright ("stat: illegal option -- c").
#
# This mattered: the previous version used the GNU form only, with `|| echo 0`
# as the fallback. On macOS — the platform this kit is developed on — every call
# errored, so `mtime` and `newest` were both 0, `0 -gt 0` was false, and the
# staleness branch below could never fire. The check reported success while
# evaluating nothing. A guard that silently degrades to a pass is the exact
# failure class this repo exists to catch, and it shipped inside the guard.
mtime_of() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || return 1
}

# Stale if any changed source file is newer than the last verify.
if ! mtime=$(mtime_of "$marker"); then
  # G-03: a guard that cannot evaluate its input must block, not allow.
  echo "done-check: cannot read the mtime of $marker — refusing to certify done." >&2
  echo "Neither 'stat -c %Y' (GNU) nor 'stat -f %m' (BSD) worked on this host." >&2
  exit 2
fi

newest=0
while IFS= read -r f; do
  [ -f "$root/$f" ] || continue
  if ! t=$(mtime_of "$root/$f"); then
    echo "done-check: cannot read the mtime of $f — refusing to certify done." >&2
    exit 2
  fi
  [ "$t" -gt "$newest" ] && newest=$t
done <<< "$changed"

if [ "$newest" -gt "$mtime" ]; then
  echo "Source changed after the last verify run. Re-run verify before claiming done." >&2
  exit 2
fi
exit 0
