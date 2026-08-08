#!/usr/bin/env bash
# f4d-kit PreToolUse guard. Exit 2 = hard block, stderr returned to Claude.
set -uo pipefail
input=$(cat)
target=$(printf '%s' "$input" | jq -r '.tool_input.command // .tool_input.file_path // .tool_input.path // ""' 2>/dev/null || echo "")
[ -z "$target" ] && exit 0

deny() { echo "BLOCKED by f4d-kit: $1" >&2; exit 2; }

shopt -s nocasematch
case "$target" in
  *".env"*|*"id_rsa"*|*".pem"*|*"credentials.json"*)
      deny "secret material is off-limits. Use .env.example and describe the variable instead." ;;
  *"keystore"*|*"mnemonic"*|*"seed phrase"*|*".key"*)
      deny "key material is off-limits." ;;
  *"PRIVATE_KEY"*|*"SECRET_KEY"*|*"_TOKEN="*|*"API_KEY="*)
      deny "never interpolate a credential into a command. Reference the env var by name." ;;
  *"--broadcast"*)
      deny "no transaction broadcasting from an agent session. Use anvil or a fork." ;;
  *"mainnet"*|*"infura.io"*|*"alchemy.com"*|*"polygon-rpc.com"*)
      deny "no mainnet RPC in an agent session. Use a local or forked chain." ;;
  *"rm -rf /"*|*"rm -rf ~"*|*":(){"*)
      deny "destructive command." ;;
  *"DROP DATABASE"*|*"TRUNCATE"*|*"drop schema"*)
      deny "destructive database operation. Use a migration, or scripts/dev-reset.sh locally." ;;
  *"git push --force"*|*"push -f "*)
      deny "force-push is human-only." ;;
esac
exit 0
