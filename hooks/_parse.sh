# Shared JSON field extraction. Sourced by other hooks.
#
# jq is not guaranteed present. Depending on it silently turned every hook into
# a no-op on machines without it — a guard that looks installed and enforces
# nothing. Fall back to python3, then to sed, and fail LOUD rather than allowing.
hook_field() {
  local json="$1" key="$2" out=""
  if command -v jq >/dev/null 2>&1; then
    out=$(printf '%s' "$json" | jq -r ".tool_input.${key} // \"\"" 2>/dev/null)
  elif command -v python3 >/dev/null 2>&1; then
    out=$(printf '%s' "$json" | python3 -c "
import sys,json
try: print(json.load(sys.stdin).get('tool_input',{}).get('$key','') or '')
except Exception: print('')
" 2>/dev/null)
  else
    out=$(printf '%s' "$json" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1)
  fi
  printf '%s' "$out"
}

# True when the payload had content but nothing could be extracted — i.e. the
# parser failed rather than the field being genuinely absent.
hook_parse_failed() {
  local json="$1"
  [ -n "$json" ] && ! printf '%s' "$json" | grep -q '"tool_input"'
}

# A10 — enforcement telemetry. Appends: ISO-time <TAB> rule_id <TAB> detail
# to .claude/.enforcement-log at the repo root of the cwd.
#
# HARD PROPERTY: this function must never change control flow. Every failure
# path returns 0 — an unwritable log must never weaken a deny, and a deny must
# never be delayed waiting on telemetry. The guard blocks; the log is a bonus.
log_deny() {
  local rule="$1" detail="${2-}"
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  mkdir -p "$root/.claude" 2>/dev/null || return 0
  # FAIL-CLOSED for secret-class rules: a C-01/KS-* deny is EXPECTED to carry a
  # secret somewhere in the command — as an assignment, a redirect target's
  # payload, or a key embedded in an RPC URL. No regex can enumerate those
  # shapes, so for these rules the detail is withheld entirely; the rule id and
  # timestamp are the telemetry. For every other rule, assignment-shaped values
  # are redacted as defense in depth.
  case "$rule" in
    C-01|KS-01|KS-02) detail="[withheld — secret-class deny]" ;;
    *)
      detail=$(printf '%s' "$detail" \
        | sed -E 's/([A-Za-z_]*(KEY|TOKEN|SECRET|PASS(WORD)?|MNEMONIC|CREDENTIAL)[A-Za-z_]*[[:space:]]*=)[^[:space:]]+/\1[REDACTED]/Ig' \
        2>/dev/null) || detail="[redaction failed — detail withheld]" ;;
  esac
  printf '%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rule" "$(printf '%s' "$detail" | head -c 120 | tr '\n\t' '  ')" \
    >> "$root/.claude/.enforcement-log" 2>/dev/null || true
  return 0
}
