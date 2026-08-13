#!/usr/bin/env bash
# SessionStart hook. A15 DECIDED 2026-08-11 — re-scoped, kept:
#
#   PRIMARY JOB: session telemetry. This hook writes .claude/.session-log —
#   the evidence session_report.py, /retro, and /promote-rule run on. Retiring
#   it retires the evidence.
#   SECONDARY: the rules-index injection is redundant defense-in-depth.
#   Empirically proven redundant on Claude Code 2.1.220 (sentinel rule in
#   .claude/rules/ loaded headlessly with NO hook and no settings.json) —
#   kept only for older CLIs and --setting-sources exclusions.
#
# AGENTS.md-style guides still never auto-load; the documented fix there is an
# @AGENTS.md import in CLAUDE.md, not this hook.
#
# This hook walks up to the repo root and injects the rules index into every
# session regardless of where it started.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_parse.sh"
hook_opted_in || exit 0

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
# ── Telemetry ────────────────────────────────────────────────────────────
# "Observe for a week" is not something an agent can do — every session starts
# blank. So the observation is written down instead of remembered.
# /project-audit reads this log and reports on real counts, not recollection.
log="$root/.claude/.session-log"
mkdir -p "$(dirname "$log")" 2>/dev/null
{
  printf '%s\t' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\t' "$([ "$cwd" = "$root" ] && echo "root" || echo "subdir")"
  printf '%s\t' "$(printf '%s' "${cwd#$root}" | sed 's|^/||' | cut -c1-40)"
  printf '%s\t' "$([ -f "$root/CLAUDE.md" ] && echo "claudemd" || echo "no-claudemd")"
  printf '%s\n' "$(ls "$root/.claude/rules"/*.md 2>/dev/null | wc -l | tr -d ' ')rules"
} >> "$log" 2>/dev/null

echo "=== END PROJECT RULES ==="
exit 0
