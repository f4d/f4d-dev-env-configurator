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
