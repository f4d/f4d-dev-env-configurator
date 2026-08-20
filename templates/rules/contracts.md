---
id: contracts
always_apply: false
---
# Contracts (multi-repo)

- The contract repo is the source of truth for every cross-repo payload, endpoint, and event.
- Types are GENERATED from the spec and committed as generated. Never hand-edit, never re-declare a shape locally.
- This repo pins a contract version. Bumping it is its own commit with its own PR.
- A change to a shared shape starts in the contract repo, ships as a version, and only then lands here.
- Additive changes are minor bumps. Removing or retyping a field is a major bump and requires every consumer to be checked.
- Before opening a PR, run the drift check against the pinned contract version.
