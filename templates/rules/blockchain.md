---
id: blockchain
always_apply: false
---
# Blockchain

- Foundry for contracts. `forge fmt --check`, `forge test`, and `forge snapshot --check` are part of verify.
- `.gas-snapshot` is committed. An unexplained gas change is a review blocker.
- Checks-Effects-Interactions ordering, always. Reentrancy guard on anything touching value.
- Custom errors over revert strings. No `tx.origin`. No unchecked external call returns.
- Test against a forked chain via `anvil --fork-url`. Never against mainnet directly.
- NEVER broadcast a transaction from an agent session. `--broadcast` is human-run, from a human terminal.
- Every contract has invariant tests, not only unit tests.
- Upgradeability, if used, has an explicit storage-layout test between versions.
