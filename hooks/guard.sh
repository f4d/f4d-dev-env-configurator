#!/usr/bin/env bash
# f4d-kit PreToolUse guard. Exit 2 = hard block, stderr returned to Claude.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_parse.sh"

input=$(cat)
cmd=$(hook_field "$input" "command")
[ -z "$cmd" ] && cmd=$(hook_field "$input" "file_path")
[ -z "$cmd" ] && cmd=$(hook_field "$input" "path")

# A guard that cannot read its input must not pretend to pass.
if [ -z "$cmd" ] && hook_parse_failed "$input"; then
  log_deny "G-03" "unparseable tool input"
  echo "BLOCKED: guard.sh could not parse the tool input, so it cannot verify safety." >&2
  echo "Install jq or python3, or fix the hook. Refusing to allow unverified." >&2
  exit 2
fi
[ -z "$cmd" ] && exit 0

# deny <rule-id> <message>. UNREGISTERED = the guard enforces something the
# registry holds no row for — a registry-honesty gap, logged as itself.
deny() { log_deny "$1" "$cmd"; echo "BLOCKED by f4d-kit [$1]: $2" >&2; exit 2; }

shopt -s nocasematch
case "$cmd" in
  *".env"*|*"id_rsa"*|*".pem"*|*"credentials.json"*)
      deny "C-01" "secret material is off-limits. Use .env.example and describe the variable instead." ;;
  *"keystore"*|*"mnemonic"*|*"seed phrase"*|*".key"*)
      deny "C-01" "key material is off-limits." ;;
  *"PRIVATE_KEY"*|*"SECRET_KEY"*|*"_TOKEN="*|*"API_KEY="*)
      deny "C-01" "never interpolate a credential into a command. Reference the env var by name." ;;
  *"--broadcast"*)
      deny "UNREGISTERED" "no transaction broadcasting from an agent session. Use anvil or a fork." ;;
  *"mainnet"*|*"infura.io"*|*"alchemy.com"*|*"polygon-rpc.com"*)
      deny "UNREGISTERED" "no mainnet RPC in an agent session. Use a local or forked chain." ;;
  *"rm -rf /"*|*"rm -rf ~"*|*":(){"*)
      deny "UNREGISTERED" "destructive command." ;;
  *"DROP DATABASE"*|*"TRUNCATE"*|*"drop schema"*)
      deny "C-03" "destructive database operation. Use a migration, or scripts/dev-reset.sh locally." ;;
  *"git push --force"*|*"push -f "*)
      deny "C-02" "force-push is human-only." ;;
esac
exit 0
