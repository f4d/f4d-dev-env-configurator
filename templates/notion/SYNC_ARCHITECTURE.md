# Sync architecture — two paths

The kit ships **Path A** because it works today. **Path B** is where this goes when Notion's Workers platform leaves beta. Design decisions below are made so the migration is a swap, not a rewrite.

---

## Path A — GitHub Actions → Notion API *(shipped, default)*

`.github/workflows/notion-sync.yml` + `.github/scripts/notion_sync.py`

| | |
|---|---|
| Runs on | GitHub Actions |
| Trigger | `issues` and `pull_request` events |
| Credentials | `NOTION_TOKEN` secret + `NOTION_WORK_DB` variable, per org |
| Direction | GitHub → Notion, push |
| Maintenance | The script is yours. Notion API version pinning is yours. |

**Why it ships first:** no beta dependency, no waitlist, no new runtime. Every piece is something you already operate.

**What it costs:** a script in every repo, a secret in every org, and an Actions run per event.

---

## Path B — Notion Workers *(target)*

Notion's developer platform provides a hosted runtime — <cite>Workers are isolated sandboxes managed by Notion, so the code behind your syncs, tools, and workflows runs on their infra instead of your servers.</cite> Deployed with `ntn deploy worker`.

Three capabilities matter here, all currently in **beta**:

**Syncs** — <cite>continuously upsert external records into a Notion Database with Workers, a declarative schema, and a persistent cursor.</cite> A scheduled `worker.sync()` pulls GitHub issues on an interval, with the cursor handled for you. This replaces `notion_sync.py` entirely.

**Webhooks** — <cite>listen for incoming webhooks from any app, then run workflows with Notion Agents, pages, databases, and external APIs.</cite> A GitHub `pull_request` webhook hits the worker directly. No Actions run, no secret in GitHub.

**Agent tools** — `worker.tool()` defines custom tools a Notion Agent can call. This is how the Work DB stops being a passive mirror: a tool that queries GitHub, or reads a spec file from a repo, becomes callable from inside Notion.

### What changes when you migrate

| | Path A | Path B |
|---|---|---|
| Sync code lives in | Every repo | One worker, deployed once |
| Secrets in GitHub | `NOTION_TOKEN` per org | None — the worker holds its own |
| New repo onboarding | Copy two files, add to select options | Add to select options only |
| Failure surface | Actions logs, per repo | Worker logs, one place |
| Schema drift | Manual | Declarative — schema is code |

The declarative schema is the real win. Path A's schema lives in a markdown file that can silently disagree with the actual database. Path B's schema *is* the database definition.

---

## Path C — External Agents *(alpha, waitlist)*

Notion's External Agents API brings agents like Claude into Notion as collaborators: <cite>@mention them in any page, comment, or chat with them directly</cite>, and <cite>hand off work to your agents from any task, or trigger them in parallel.</cite>

If this lands, assigning a Work DB row to Claude becomes a native action — no `@claude` comment on a GitHub issue, no Action run. The triage board becomes the delegation surface directly.

**Status: alpha, waitlist only.** Do not design around it. Do join the waitlist, because it collapses two systems into one if it ships.

---

## Migration triggers

Record these as the `Revisit when` condition on the sync ADR:

- **Move to Path B** when Notion Workers syncs and webhooks leave beta, *or* when the third repo needs wiring — at three copies of `notion_sync.py`, the duplication cost exceeds the beta risk.
- **Adopt Path C** when External Agents leaves alpha and supports Claude Code specifically.
- **Stay on Path A** if neither happens. It is not fragile; it is just more copies than necessary.

## What to keep stable across all three

These are why the migration is a swap rather than a rewrite. Do not let them drift:

1. **Field ownership.** The sync writes only its eleven fields. Triage fields are never touched by any path.
2. **The Work DB schema** is the contract. Both paths write the same property names and types.
3. **Rows originate from GitHub issues.** No orphan rows, in any path.
4. **One direction.** No path writes GitHub state from Notion. Creating an issue from a row is a separate, explicit action.
