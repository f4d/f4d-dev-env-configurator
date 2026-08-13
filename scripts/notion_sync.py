#!/usr/bin/env python3
"""
f4d-kit — GitHub → Notion work sync.

Runs in GitHub Actions. Pushes engineering state into the company Work DB.
One direction only: GitHub owns state, Notion owns triage.

Never writes triage fields (Class, Size, Priority, Stage, Area, Launch, Notes).
Those belong to the human and are preserved on every update.

Env:
  NOTION_TOKEN     Notion integration token
  NOTION_WORK_DB   data source id of the Work DB
  GITHUB_TOKEN     fetches the real issue when a PR links one Notion has not seen yet
  GITHUB_REPOSITORY, GITHUB_EVENT_PATH  provided by Actions
"""
import json
import os
import sys
import urllib.error
import urllib.request

NOTION_TOKEN = os.environ["NOTION_TOKEN"]
WORK_DB = os.environ["NOTION_WORK_DB"]
REPO = os.environ["GITHUB_REPOSITORY"]
GITHUB_TOKEN = os.environ["GITHUB_TOKEN"]
API = "https://api.notion.com/v1"
HEADERS = {
    "Authorization": f"Bearer {NOTION_TOKEN}",
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json",
}
# Seconds to wait on a single request before giving up. Without this, a
# connection Notion (or GitHub) accepts but stalls on can occupy the job
# until the runner's own limit — which, sharing a concurrency key with
# every other notion-sync run for the repo, blocks all of them behind it.
REQUEST_TIMEOUT = 30

# Fields the sync owns. Everything else in the row is left untouched.
OWNED = {
    "Title", "Issue", "Repo", "State", "Issue URL", "PR URL",
    "Branch", "Commit", "CI", "GH Labels", "Opened", "Merged", "Synced",
}


def call(method, path, payload=None):
    req = urllib.request.Request(
        f"{API}{path}",
        method=method,
        headers=HEADERS,
        data=json.dumps(payload).encode() if payload else None,
    )
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        print(f"Notion API {e.code}: {e.read().decode()[:500]}", file=sys.stderr)
        raise
    except (urllib.error.URLError, TimeoutError) as e:
        print(f"Notion API request failed: {e}", file=sys.stderr)
        raise


def find_row(issue_number):
    """Locate an existing row by repo + issue number. Returns page id or None."""
    res = call("POST", f"/databases/{WORK_DB}/query", {
        "filter": {"and": [
            {"property": "Issue", "number": {"equals": issue_number}},
            {"property": "Repo", "select": {"equals": REPO}},
        ]},
        "page_size": 1,
    })
    results = res.get("results", [])
    return results[0]["id"] if results else None


def fetch_issue(number):
    """Fetch the real issue from the GitHub API.

    Used only to seed a brand-new row when a PR is the first event this
    sync has ever seen for its linked issue. Deliberately never fabricates
    Title/Opened/GH Labels from the PR — those are issue-owned fields, and
    a PR can legitimately differ from the issue it closes.

    Soft-fails (returns None) rather than raising: an unresolvable issue
    number (bad cross-repo reference, deleted issue) or a flaky GitHub API
    call should skip this one sync, not fail the whole job the way a
    Notion write failure does — nothing has been written yet, so there is
    nothing a skip could corrupt.
    """
    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/issues/{number}",
        headers={
            "Authorization": f"Bearer {GITHUB_TOKEN}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:  # catch-empty-ok: logged; caller checks `if not issue` before any use
        print(f"GitHub API {e.code} fetching issue #{number}: {e.read().decode()[:500]}", file=sys.stderr)
        return None
    except (urllib.error.URLError, TimeoutError) as e:  # catch-empty-ok: logged; caller checks `if not issue` before any use
        print(f"GitHub API request failed fetching issue #{number}: {e}", file=sys.stderr)
        return None


def txt(s):
    return {"rich_text": [{"text": {"content": (s or "")[:2000]}}]}


def pr_state(pr):
    """Map a PR's GitHub state to the work item's Notion State.

    Three cases, not two. `merged` is checked independently of `state`,
    since a merged PR also reports state == "closed". A closed-and-not-
    merged PR is abandoned: it must not stay "In Review" forever waiting
    for an event that will never arrive, so it maps to "Closed" — the same
    value a closed issue with no PR gets in build_props below.
    """
    if pr.get("merged"):
        return "Merged"
    if pr.get("state") == "closed":
        return "Closed"
    return "In Review"


def pr_merge_fields(pr):
    """Merged/Commit — present only once a PR has actually merged.

    Shared by build_props and build_pr_mirror_props so the two can never
    drift on what "merged" writes.
    """
    if not pr.get("merged"):
        return {}
    return {
        "Merged": {"date": {"start": pr["merged_at"]}},
        "Commit": txt((pr.get("merge_commit_sha") or "")[:7]),
    }


def build_props(event, issue, pr, now):
    """Assemble only the fields this sync owns."""
    state = "Open"
    if pr:
        state = pr_state(pr)
    elif issue.get("state") == "closed":
        state = "Closed"

    props = {
        "Title": {"title": [{"text": {"content": issue["title"][:200]}}]},
        "Issue": {"number": issue["number"]},
        "Repo": {"select": {"name": REPO}},
        "State": {"select": {"name": state}},
        "Issue URL": {"url": issue["html_url"]},
        "GH Labels": {"multi_select": [
            {"name": l["name"][:100]} for l in issue.get("labels", [])[:10]
        ]},
        "Opened": {"date": {"start": issue["created_at"]}},
        "Synced": {"date": {"start": now}},
    }

    if pr:
        props["PR URL"] = {"url": pr["html_url"]}
        props["Branch"] = txt(pr.get("head", {}).get("ref", ""))
        props.update(pr_merge_fields(pr))

    return props


def build_pr_mirror_props(pr, now):
    """PR-triggered update to an issue row that already exists.

    Only the fields a PR event actually owns. Never Title/Opened/GH
    Labels — those belong to the linked issue and must only ever be set
    from a real issues event. build_props would recompute them from the PR
    (title, created_at, labels) and overwrite a correct row the moment a
    PR's own title or labels differ from its issue's — which is exactly
    the corruption this function exists to avoid.
    """
    props = {
        "State": {"select": {"name": pr_state(pr)}},
        "PR URL": {"url": pr["html_url"]},
        "Branch": txt(pr.get("head", {}).get("ref", "")),
        "Synced": {"date": {"start": now}},
    }
    props.update(pr_merge_fields(pr))
    return props


def main():
    with open(os.environ["GITHUB_EVENT_PATH"]) as f:
        event = json.load(f)

    issue = event.get("issue")
    pr = event.get("pull_request")

    from datetime import datetime, timezone
    now = datetime.now(timezone.utc).isoformat()

    if pr and not issue:
        # A PR event carries no issue; resolve the linked issue number from
        # the PR body instead of fabricating issue fields from the PR.
        body = pr.get("body") or ""
        import re
        m = re.search(r"(?:closes|fixes|resolves)\s+#(\d+)", body, re.I)
        if not m:
            print("PR has no linked issue — nothing to sync.")
            return
        issue_number = int(m.group(1))

        page_id = find_row(issue_number)
        if page_id:
            # A real issues event already gave this row correct
            # Title/Opened/GH Labels — touch only the PR-owned fields.
            props = build_pr_mirror_props(pr, now)
            call("PATCH", f"/pages/{page_id}", {"properties": props})
            print(f"Updated {REPO}#{issue_number}")
            return

        # No row yet: this PR is the first touchpoint Notion has seen for
        # the issue. Seed one from the real issue — never fabricated from
        # the PR — or skip cleanly if it cannot be fetched.
        issue = fetch_issue(issue_number)
        if not issue:
            print(f"Could not fetch {REPO}#{issue_number} — nothing to sync.")
            return

    if not issue:
        print("No issue in event — nothing to sync.")
        return

    props = build_props(event, issue, pr, now)

    page_id = find_row(issue["number"])
    if page_id:
        call("PATCH", f"/pages/{page_id}", {"properties": props})
        print(f"Updated {REPO}#{issue['number']}")
    else:
        # New rows land in Triage. The human classifies from there.
        props["Stage"] = {"select": {"name": "Triage"}}
        call("POST", "/pages", {
            "parent": {"database_id": WORK_DB},
            "properties": props,
        })
        print(f"Created {REPO}#{issue['number']} in Triage")


if __name__ == "__main__":
    main()
