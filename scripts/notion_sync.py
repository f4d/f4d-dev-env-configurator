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

CLI:
  (no args)      Run the sync. Requires every env var above.
  resolve-issue  Print the linked issue number for GITHUB_EVENT_PATH's event
                 (or nothing, if none is linked) and exit 0. Requires only
                 GITHUB_EVENT_PATH — never NOTION_TOKEN/NOTION_WORK_DB/
                 GITHUB_TOKEN. Used by notion-sync.yml's `resolve` job to
                 compute the `sync` job's concurrency-group key before that
                 job (which does need those secrets) starts, so this mode
                 must stay callable without them.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request

# GitHub's full closing-keyword vocabulary (case-insensitive): close, closes,
# closed, fix, fixes, fixed, resolve, resolves, resolved. See "Linking a pull
# request to an issue" in GitHub's docs. The leading `\b` stops a keyword
# that is only a suffix of a longer word (e.g. "unresolved", "prefixes")
# from matching; the required `\s+` before the `#` stops text glued directly
# to the keyword (e.g. "closest #1") from matching either — both verified
# with negative test cases in tests/notion_sync_test.sh, not assumed.
CLOSING_KEYWORDS_RE = re.compile(
    r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)", re.I
)


def parse_linked_issue(body):
    """Return the issue number `body` closes via a GitHub closing keyword,
    or None if it names none.

    Single source of truth for two callers that must never disagree about
    which issue a PR links: main() below (which Notion row a PR event
    updates) and this file's `resolve-issue` CLI mode (the concurrency-group
    key the notion-sync workflow's `resolve` job outputs, so a PR and the
    issue it closes serialize against each other instead of racing on the
    same row — see templates/github/notion-sync.yml).
    """
    m = CLOSING_KEYWORDS_RE.search(body or "")
    return int(m.group(1)) if m else None


if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] == "resolve-issue":
    # Cheap, secret-free path for the workflow's `resolve` job: reads only
    # the event payload Actions already wrote to GITHUB_EVENT_PATH, makes no
    # network call, and must not require NOTION_TOKEN/NOTION_WORK_DB/
    # GITHUB_TOKEN — this has to succeed (or cleanly resolve nothing) before
    # the workflow can even decide the sync job's concurrency group, whether
    # or not that job's secrets are configured yet. Exits 0 whether or not
    # an issue was resolved; the workflow step tells the two cases apart by
    # checking for empty stdout, not by exit code — an unresolvable PR is a
    # normal outcome, not a failure.
    with open(os.environ["GITHUB_EVENT_PATH"]) as f:
        _event = json.load(f)
    _issue = _event.get("issue")
    _pr = _event.get("pull_request")
    if _issue and _issue.get("number") is not None:
        print(_issue["number"])
    elif _pr:
        _linked = parse_linked_issue(_pr.get("body") or "")
        if _linked is not None:
            print(_linked)
    sys.exit(0)

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
# until the runner's own limit — which, sharing a concurrency key with every
# other notion-sync run for the same linked issue (see the `sync` job's
# concurrency block in notion-sync.yml), blocks all of those behind it too.
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
        issue_number = parse_linked_issue(pr.get("body") or "")
        if issue_number is None:
            print("PR has no linked issue — nothing to sync.")
            return

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
