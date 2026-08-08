---
name: notion-sync
description: Set up and operate the Notion Work DB that mirrors GitHub issues and PRs and adds a triage layer. Use to create the Work DB for a company, wire a repo's sync workflow, triage the queue, query what is in flight, or diagnose a stale sync. Also use whenever the user asks about their work queue, open items, launch lists, what is blocked, or what shipped — the Work DB is the fastest answer to all of them.
---

# Notion Sync

Notion is the triage UX and work queue. GitHub is the system of record for engineering state. The sync is one-directional and field-scoped.

**Never write these from Notion or from Claude:** `Issue`, `Repo`, `State`, `Issue URL`, `PR URL`, `Branch`, `Commit`, `CI`, `GH Labels`, `Opened`, `Merged`, `Synced`. The workflow owns them; hand edits get overwritten.

**Freely write these:** `Class`, `Size`, `Priority`, `Stage`, `Area`, `Launch`, `Blocked By`, `Project`, `Client`, `Spec`, `ADR`, `Notes`.

---

## Mode 1 — Create the Work DB (once per company)

1. Read the company's org profile for `notion_workspace`. If absent, ask which workspace and parent page.
2. Create the database using the DDL in `${CLAUDE_PLUGIN_ROOT}/templates/notion/WORK_DB_SCHEMA.md`.
3. Create the seven views listed in that file. The **Stale** view is not optional — it is the only thing that makes a silently dead sync visible.
4. Capture the returned data source id.
5. Tell the user to do these two things themselves — never do them for them:
   - Share the database with their Notion integration (Notion UI, `...` → Connections)
   - Add `NOTION_TOKEN` as a repo or org **secret**, and `NOTION_WORK_DB` as a repo or org **variable**
6. Record the data source id in the org profile under a `notion_work_db` key.

---

## Mode 2 — Wire a repo (once per repo)

```bash
mkdir -p .github/scripts .github/workflows
cp "$CLAUDE_PLUGIN_ROOT/scripts/notion_sync.py" .github/scripts/notion_sync.py
cp "$CLAUDE_PLUGIN_ROOT/templates/github/notion-sync.yml" .github/workflows/
cp "$CLAUDE_PLUGIN_ROOT/templates/github/claude.yml" .github/workflows/
cp "$CLAUDE_PLUGIN_ROOT/templates/github/claude-code-review.yml" .github/workflows/
git add .github
git commit -m "chore: wire notion sync and claude workflows"
git push
```

Then add this repo to the `Repo` select options in Notion, and set the `Project` default.

Verify by opening a throwaway issue and confirming a row appears in Triage. Close it and delete the row.

---

## Mode 3 — Triage (daily)

Query the **Triage** view. For each row, `/work-intake` classifies and sizes it. Write `Class`, `Size`, `Priority`, `Area`, and set `Stage`:

| Route | Stage becomes |
|---|---|
| Small and clear → straight to build | `Ready` |
| Needs a spec | `Spec`, then `/write-spec` and paste the URL into `Spec` |
| Needs a decision first | `Spec`, `Blocked By` = the ADR |
| Not now | `Parked` with a reason in `Notes` |

For anything moving to `Ready` that is small enough to delegate, comment `@claude <what to do>` on the GitHub issue. The workflow picks it up and opens a PR; the sync moves `State` on its own.

---

## Mode 4 — Query (any time)

The Work DB answers most "where are we" questions in one call. Useful shapes:

- **In flight now** — `State != Closed AND Stage != Triage`
- **This week** — `Priority in (P0, P1)`
- **Blocked** — `Blocked By is not empty`
- **A launch** — `Launch = X`, grouped by Stage
- **Shipped for a client last month** — `Client = X AND Merged within last month` → returns titles, PRs, commit SHAs, and spec links together
- **Sync health** — `Synced before 7 days ago AND State != Closed`

When answering from this DB, lead with what the user asked and attach the commit SHA or PR only when it changes what they'd do next.

---

## Mode 5 — Diagnose a stale sync

If the **Stale** view has rows:

1. Check the repo's Actions tab for failed `notion-sync` runs
2. Most common causes, in order: `NOTION_TOKEN` not shared with the database in the Notion UI; `NOTION_WORK_DB` variable missing or pointing at the database id instead of the data source id; a `Repo` select option that does not exist yet
3. Re-run the failed workflow rather than editing rows by hand

Never fix a stale row by editing it in Notion. That hides the failure and it will recur.
