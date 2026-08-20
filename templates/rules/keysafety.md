---
id: keysafety
always_apply: false
---
# Key Safety

Non-negotiable. Enforced by hook, restated here for clarity.

- Never read, print, echo, interpolate, or write a private key, mnemonic, seed phrase, or keystore file.
- Never open `.env`, `*.key`, `*.pem`, or any keystore path.
- Never place a credential in a command argument, a URL, or a log line.
- Mainnet RPC endpoints are off-limits in agent sessions. Local chain or fork only.
- If a task appears to require a real key, stop and say so. Do not work around it.
