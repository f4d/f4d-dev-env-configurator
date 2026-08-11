#!/usr/bin/env bash
# f4d-kit FALLBACK guard (A11) — written INTO the repo by /project-init.
#
# Every other guard lives at ${CLAUDE_PLUGIN_ROOT}/... — if the plugin is
# uninstalled, disabled, or missing on a new machine, those hooks silently
# vanish and the repo looks fine. Absence reads as permission. This file is the
# floor that survives: SELF-CONTAINED (no plugin paths, no shared libs),
# covering only the never-acceptable class — secret material (C-01) and
# force-push (C-02). It runs ALONGSIDE the plugin guard when both exist; A6
# proved any exit-2 blocks regardless of order, so double-wiring is safe.
#
# No telemetry here by design: the fallback's one job is to still block when
# everything else is gone, with zero dependencies that could take it down too.
set -uo pipefail

input=$(cat)

field() {  # minimal, dependency-free extraction of "name":"value"
  printf '%s' "$input" | sed -nE 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -1
}

cmd=$(field "command")
[ -z "$cmd" ] && cmd=$(field "file_path")
[ -z "$cmd" ] && cmd=$(field "path")

# G-03: a guard that cannot read its input must block, not shrug. Wired with a
# matcher, so every payload must yield a field — a bare "tool_input" key is not
# proof of anything ({"tool_input":{}} and truncated payloads must block).
if [ -z "$cmd" ] && [ -n "$input" ]; then
  echo "BLOCKED by guard-local [G-03]: could not extract a command or path from the tool input; refusing to allow unverified." >&2
  exit 2
fi
[ -z "$cmd" ] && exit 0

shopt -s nocasematch
case "$cmd" in
  *".env"*|*"id_rsa"*|*".pem"*|*"credentials.json"*|*"keystore"*|*"mnemonic"*|*".key"*|*"PRIVATE_KEY"*|*"SECRET_KEY"*|*"_TOKEN="*|*"API_KEY="*)
    echo "BLOCKED by guard-local [C-01]: secret material is off-limits (fallback guard — plugin may be absent)." >&2
    exit 2 ;;
  *"git push --force"*|*"push -f "*|*"push -f")
    echo "BLOCKED by guard-local [C-02]: force-push is human-only (fallback guard — plugin may be absent)." >&2
    exit 2 ;;
esac
exit 0
