# 002 — GitHub Issues + Projects + Actions as the work tracker

- **Status:** Accepted
- **Date:** 2026-08-08

## Context
Needed a work tracker that supports triage, a queue, and — critically —
automation: bug intake, agent-driven fixes, automatic code review, and CI.

## Decision
GitHub Issues and org-level Projects for tracking; GitHub Actions for automation.
Notion holds the triage UX and business context via one-directional sync.

## Alternatives considered

| Option | Why not |
|---|---|
| Linear + Cyrus | Better triage UX, but Claude Code integration is third-party and self-hosted. Three moving parts instead of one, and every automation named still runs in Actions regardless. |
| Notion alone | Cannot do triage rules, agent delegation, or git-derived status. A Zapier approximation would be brittle at every joint. |
| Jira | Weight far exceeds the need at this scale. |

## Trade-off
GitHub's triage UX is genuinely weaker than Linear's. That is the price paid for
first-party agent integration and one system instead of three.

## Consequences
**Accepted costs:** weak triage view — mitigated by the Notion Work DB. Cross-org
visibility requires a script, not a feature.

**Reversal cost:** moderate. Issues export; the Notion layer is unaffected.

**Revisit when:** bug volume makes GitHub's triage view painful, or Anthropic
ships a native Linear agent.
