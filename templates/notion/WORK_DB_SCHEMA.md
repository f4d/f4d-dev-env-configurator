# Work DB — Notion schema

One database per company workspace. Every repo in that company feeds it. This is the triage surface and the work queue; GitHub remains the system of record for engineering state.

## Ownership rule

| Group | Written by | Editable by hand? |
|---|---|---|
| GitHub mirror fields | The sync workflow only | **No.** Edits are overwritten on next sync. |
| Triage fields | You, in Notion | Yes — this is the point |
| Context fields | You, or Claude | Yes |

If you find yourself wanting to edit a mirror field, the change belongs in GitHub.

---

## Create statement

```sql
CREATE TABLE (
  "Title"          TITLE,

  -- ── GitHub mirror — sync writes these, never edit by hand ──
  "Issue"          NUMBER COMMENT 'GitHub issue number',
  "Repo"           SELECT('':default) COMMENT 'owner/repo — options added as repos join',
  "State"          SELECT('Open':blue, 'In Progress':yellow, 'In Review':orange, 'Merged':green, 'Closed':gray),
  "Issue URL"      URL,
  "PR URL"         URL,
  "Branch"         RICH_TEXT,
  "Commit"         RICH_TEXT COMMENT 'merge commit SHA, short',
  "CI"             SELECT('passing':green, 'failing':red, 'pending':yellow, 'n/a':gray),
  "GH Labels"      MULTI_SELECT(),
  "Opened"         DATE,
  "Merged"         DATE,
  "Synced"         DATE COMMENT 'last sync timestamp — staleness check',

  -- ── Triage — yours ──
  "Class"          SELECT('Bug':red, 'Chore':gray, 'Feature':blue, 'Question':purple),
  "Size"           SELECT('S':green, 'M':yellow, 'L':red),
  "Priority"       SELECT('P0 now':red, 'P1 this week':orange, 'P2 soon':yellow, 'P3 someday':gray),
  "Stage"          SELECT('Triage':purple, 'Spec':blue, 'Ready':green, 'Building':yellow, 'Review':orange, 'Shipped':green, 'Parked':gray),
  "Area"           MULTI_SELECT('api':blue, 'db':green, 'integrations':purple, 'frontend':pink, 'infra':gray, 'docs':brown),
  "Launch"         SELECT() COMMENT 'launch or milestone grouping — options added as needed',
  "Blocked By"     RICH_TEXT,

  -- ── Context — yours or Claude's ──
  "Project"        SELECT() COMMENT 'repo-level project name',
  "Client"         RICH_TEXT,
  "Spec"           URL COMMENT 'link to docs/specs/NNN in the repo',
  "ADR"            URL COMMENT 'link to docs/decisions/NNN in the repo',
  "Notes"          RICH_TEXT COMMENT 'business context Claude should know but code cannot tell it',

  "Created"        CREATED_TIME,
  "Updated"        LAST_EDITED_TIME
)
```

`Class`, `Size`, and `Stage` deliberately mirror the lifecycle in `templates/process/LIFECYCLE.md` so `/work-intake` writes straight into them.

---

## Views to create

| View | Type | Config |
|---|---|---|
| **Triage** | Board, grouped by Class | `FILTER "Stage" = "Triage"` — the daily front door |
| **This week** | Table | `FILTER "Priority" = "P0 now" OR "Priority" = "P1 this week"; SORT BY "Priority" ASC` |
| **In flight** | Board, grouped by Stage | `FILTER "State" != "Closed" AND "Stage" != "Triage"` |
| **By launch** | Board, grouped by Launch | everything not Shipped |
| **By area** | Board, grouped by Area | cross-project view of where work is concentrated |
| **By project** | Board, grouped by Project | the per-repo cut |
| **Stale** | Table | `FILTER "Synced" is before 7 days ago AND "State" != "Closed"` — catches sync failures |

The **Stale** view is the one people skip and then regret. A sync that quietly stops looks exactly like a quiet week.

---

## What Claude gets from this

When `/work-intake` or any session queries the Work DB via the Notion MCP, it gets in one call what would otherwise take several GitHub API calls plus context you'd have to type: what's in flight, what's blocked and by what, which launch an item belongs to, the client context, and links to the spec and ADR — with the commit SHA and PR that closed it already attached.

That last part is the payoff. "What did we ship for this client last month, and why did we do it that way" becomes one query returning issues, commits, specs, and decisions together.
