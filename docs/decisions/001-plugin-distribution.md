# 001 — Distribute the framework as a Claude Code plugin

- **Status:** Accepted
- **Date:** 2026-08-08

## Context
The framework must reach many repos across several companies and stay consistent
as it evolves. Repos are standalone, not a monorepo.

## Decision
We distribute f4d-kit as a Claude Code plugin installed per repo, versioned with
semver, pinned per project.

## Alternatives considered

| Option | Why not |
|---|---|
| GitHub repo template | Applies once at creation. No mechanism to propagate a later change to repos already created — the exact failure this framework exists to prevent. |
| Copy `.claude/` into each repo | N copies, guaranteed drift, no version signal. Violates S-05 at the framework level. |
| Git submodule | Propagates, but submodules are widely misoperated and a stale pointer is invisible. |
| npm/pip package | Works for scripts, not for skills, hooks, or agents, which the harness loads from plugin paths. |

## Consequences
**Accepted costs:** the plugin is a single point of failure — if it is not
installed, every hook silently disappears (see A11). Mitigated by a fallback
`guard.sh` written into each repo and a plugin-presence check in `/project-audit`.

**Reversal cost:** low. The plugin is files; they could be vendored per repo in an
afternoon, at the cost of drift.

**Revisit when:** the plugin mechanism changes materially, or a project needs the
framework outside Claude Code.
