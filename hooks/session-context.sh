#!/usr/bin/env bash
# SessionStart hook — fixes the load-path defect.
#
# CLAUDE.md and AGENTS.md only auto-load from the directory a session starts in.
# A session started in dist/, packages/x/, or any subdirectory never sees the
# repo-root instruction files. That is a configuration defect, not a discipline
# problem: no amount of "remember to read the rules" fixes it.
#
# This hook walks up to the repo root and injects the rules index into every
# session regardless of where it started.
set -uo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cwd=$(pwd)

echo "=== PROJECT RULES (injected — cwd is $cwd) ==="

if [ "$cwd" != "$root" ]; then
  echo "NOTE: this session did not start at the repo root ($root)."
  echo "Repo-root instruction files do NOT auto-load here. They are injected below."
fi

[ -f "$root/CLAUDE.md" ] && { echo "--- CLAUDE.md ---"; cat "$root/CLAUDE.md"; }

if [ -d "$root/.claude/rules" ]; then
  echo "--- .claude/rules/ (read the relevant file before working in that area) ---"
  for f in "$root"/.claude/rules/*.md; do
    [ -e "$f" ] || continue
    echo "  $(basename "$f") — $(head -3 "$f" | grep -v '^#' | grep -v '^$' | head -1)"
  done
fi

# Enforcement reminder. The point is that prose is ignorable and hooks are not.
cat <<'EOF'
--- ENFORCEMENT ---
Hooks execute; they are not advisory. If a hook blocks you, the answer is to
change the approach, never to work around the hook.
Rules in .claude/rules/ are prose and therefore ignorable — which is exactly why
anything load-bearing should have become a hook or a test. If you find yourself
relying on a prose rule to prevent something expensive, say so: that rule is
mis-classified and belongs in .claude/hooks/ or the test suite.
EOF
echo "=== END PROJECT RULES ==="
exit 0
