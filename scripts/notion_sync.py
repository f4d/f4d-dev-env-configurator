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
  GITHUB_TOKEN     provided by Actions
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
API = "https://api.notion.com/v1"
HEADERS = {
    "Authorization": f"Bearer {NOTION_TOKEN}",
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json",
}

# Fields the sync owns. Everything else in the row is left untouched.
OWNED = {
    "Issue", "Repo", "State", "Issue URL", "PR URL",
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
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        print(f"Notion API {e.code}: {e.read().decode()[:500]}", file=sys.stderr)
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


def txt(s):
    return {"rich_text": [{"text": {"content": (s or "")[:2000]}}]}


def build_props(event, issue, pr, now):
    """Assemble only the fields this sync owns."""
    state = "Open"
    if pr:
        state = "Merged" if pr.get("merged") else "In Review"
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
        if pr.get("merged"):
            props["Merged"] = {"date": {"start": pr["merged_at"]}}
            props["Commit"] = txt((pr.get("merge_commit_sha") or "")[:7])

    return props


def main():
    with open(os.environ["GITHUB_EVENT_PATH"]) as f:
        event = json.load(f)

    issue = event.get("issue")
    pr = event.get("pull_request")

    # A PR event carries no issue; resolve the linked issue from the body.
    if pr and not issue:
        body = pr.get("body") or ""
        import re
        m = re.search(r"(?:closes|fixes|resolves)\s+#(\d+)", body, re.I)
        if not m:
            print("PR has no linked issue — nothing to sync.")
            return
        issue = {
            "number": int(m.group(1)),
            "title": pr["title"],
            "html_url": f"https://github.com/{REPO}/issues/{m.group(1)}",
            "created_at": pr["created_at"],
            "state": "open",
            "labels": pr.get("labels", []),
        }

    if not issue:
        print("No issue in event — nothing to sync.")
        return

    from datetime import datetime, timezone
    now = datetime.now(timezone.utc).isoformat()
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
