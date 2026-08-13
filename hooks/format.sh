#!/usr/bin/env bash
# f4d-kit PostToolUse formatter. Best-effort, never blocks.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_parse.sh"
hook_opted_in || exit 0
files="${CLAUDE_FILE_PATHS:-}"
[ -z "$files" ] && exit 0
for f in $files; do
  case "$f" in
    *.py)  command -v uv >/dev/null && uv run ruff format "$f" >/dev/null 2>&1 ;;
    *.ts|*.tsx|*.js|*.jsx|*.json|*.md)
           command -v pnpm >/dev/null && pnpm exec prettier --write "$f" >/dev/null 2>&1 ;;
    *.sol) command -v forge >/dev/null && forge fmt "$f" >/dev/null 2>&1 ;;
  esac
done
exit 0
