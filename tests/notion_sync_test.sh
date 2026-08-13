#!/usr/bin/env bash
# Red-then-green harness for the 2026-08-13 notion-sync review findings.
# scripts/notion_sync.py had no test coverage before this file — these are
# the first unit tests it has ever had. Every check below was run against
# the pre-fix templates/code and observed to fail before the fix landed;
# see docs/BACKLOG.md for the captured red-run transcript.
#
# Findings 1 and 2 are GitHub Actions trigger/concurrency semantics — no
# live Actions run is needed to prove them, but the exact parsed values are
# asserted here too, as cheap regression insurance (PyYAML's SafeLoader
# resolves the bare `on:` key to the boolean True under YAML 1.1 — the
# "Norway problem" — which is why the checks below index doc[True], not
# doc["on"]; verified empirically before writing these, not assumed).
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$KIT/scripts"
pass=0; fail=0
check() { if [ "$2" -eq "$3" ]; then pass=$((pass+1)); echo "  PASS  $1"; else fail=$((fail+1)); echo "  FAIL  $1 (expected exit $2, got $3)"; fi }

# Dependency preflight — fail loud once (G-03), matching conformance_test.sh.
if ! python3 -c "import yaml" 2>/dev/null; then
  echo "  FAIL  PyYAML is required for the YAML checks: pip3 install pyyaml"
  echo "pass=0 fail=1"
  exit 1
fi

echo "Finding 1 — claude-code-review.yml: ready_for_review trigger"
python3 - "$KIT/templates/github/claude-code-review.yml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
types = doc[True]["pull_request"]["types"]
job_if = doc["jobs"]["review"].get("if", "")
ok = "ready_for_review" in types and "draft == false" in job_if
if not ok:
    print(f"    types={types!r} draft-guard-present={'draft == false' in job_if!r}", file=sys.stderr)
sys.exit(0 if ok else 1)
PY
check "types includes ready_for_review, draft guard still present" 0 $?

python3 - "$KIT/templates/github/claude-code-review.yml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
types = doc[True]["pull_request"]["types"]
sys.exit(0 if ("opened" in types and "synchronize" in types) else 1)
PY
check "opened and synchronize still present (no regression)" 0 $?

echo
echo "Finding 2 — notion-sync.yml: shared concurrency key"
python3 - "$KIT/templates/github/notion-sync.yml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
group = doc["concurrency"]["group"]
per_event_keyed = "github.event.issue.number" in group or "github.event.pull_request.number" in group
repo_keyed = "github.repository" in group
if per_event_keyed or not repo_keyed:
    print(f"    group={group!r}", file=sys.stderr)
sys.exit(0 if (repo_keyed and not per_event_keyed) else 1)
PY
check "concurrency group is repo-wide, not per-issue/PR number" 0 $?

echo
echo "Finding 4 — scripts/notion_sync.py: closed-unmerged PR state"
python3 - "$SCRIPTS" <<'PY'
import sys, os
sys.path.insert(0, sys.argv[1])
os.environ.update({"NOTION_TOKEN": "t", "NOTION_WORK_DB": "w",
                    "GITHUB_REPOSITORY": "f4d/test-repo", "GITHUB_TOKEN": "g"})
import notion_sync as ns

issue = {"title": "x", "number": 1, "html_url": "u", "created_at": "c", "state": "open", "labels": []}
pr = {"merged": True, "state": "closed", "html_url": "u", "merged_at": "m",
      "merge_commit_sha": "abc1234", "head": {"ref": "b"}}
props = ns.build_props({}, issue, pr, "now")
sys.exit(0 if props["State"]["select"]["name"] == "Merged" else 1)
PY
check "merged PR -> Merged (regression)" 0 $?

python3 - "$SCRIPTS" <<'PY'
import sys, os
sys.path.insert(0, sys.argv[1])
os.environ.update({"NOTION_TOKEN": "t", "NOTION_WORK_DB": "w",
                    "GITHUB_REPOSITORY": "f4d/test-repo", "GITHUB_TOKEN": "g"})
import notion_sync as ns

issue = {"title": "x", "number": 1, "html_url": "u", "created_at": "c", "state": "open", "labels": []}
pr = {"merged": False, "state": "open", "html_url": "u", "head": {"ref": "b"}}
props = ns.build_props({}, issue, pr, "now")
sys.exit(0 if props["State"]["select"]["name"] == "In Review" else 1)
PY
check "open, unmerged PR -> In Review (regression)" 0 $?

python3 - "$SCRIPTS" <<'PY'
import sys, os
sys.path.insert(0, sys.argv[1])
os.environ.update({"NOTION_TOKEN": "t", "NOTION_WORK_DB": "w",
                    "GITHUB_REPOSITORY": "f4d/test-repo", "GITHUB_TOKEN": "g"})
import notion_sync as ns

issue = {"title": "x", "number": 1, "html_url": "u", "created_at": "c", "state": "open", "labels": []}
# Abandoned: closed without merging. Pre-fix this lands on "In Review" and
# nothing ever corrects it, since the issue stays open and no later event
# touches this row.
pr = {"merged": False, "state": "closed", "html_url": "u", "head": {"ref": "b"}}
props = ns.build_props({}, issue, pr, "now")
got = props["State"]["select"]["name"]
if got != "Closed":
    print(f"    got State={got!r}, want Closed", file=sys.stderr)
sys.exit(0 if got == "Closed" else 1)
PY
check "closed, unmerged PR -> Closed (was: stuck In Review forever)" 0 $?

echo
echo "Finding 3 — scripts/notion_sync.py: PR events must not corrupt issue-owned fields"

# 3a. Issue #12 already has a Notion row. A PR that closes #12 has a
# different title and labels. The PATCH must not touch Title/Opened/GH
# Labels — those belong to the issue, not the PR.
python3 - "$SCRIPTS" <<'PY'
import sys, os, json, urllib.error
from unittest import mock

sys.path.insert(0, sys.argv[1])
os.environ.update({"NOTION_TOKEN": "t", "NOTION_WORK_DB": "w",
                    "GITHUB_REPOSITORY": "f4d/test-repo", "GITHUB_TOKEN": "g"})
import notion_sync as ns

event = {"pull_request": {
    "number": 45,
    "title": "PR-side title (must never become the issue title)",
    "body": "Closes #12",
    "html_url": "https://github.com/f4d/test-repo/pull/45",
    "created_at": "2026-01-01T00:00:00Z",
    "state": "open",
    "merged": False,
    "head": {"ref": "fix/pr-title-mismatch"},
    "labels": [{"name": "pr-only-label"}],
}}

evt_path = "/tmp/notion_sync_test_event_3a.json"
json.dump(event, open(evt_path, "w"))
os.environ["GITHUB_EVENT_PATH"] = evt_path

captured = {}

class FakeResponse:
    def __init__(self, payload):
        self._body = json.dumps(payload).encode()
    def read(self):
        return self._body
    def __enter__(self):
        return self
    def __exit__(self, *a):
        return False

def fake_urlopen(req, timeout=None):
    url = req.full_url
    method = req.get_method()
    if url.endswith("/query"):
        return FakeResponse({"results": [{"id": "row-12-existing"}]})
    if "/pages/row-12-existing" in url and method == "PATCH":
        captured["patch_props"] = json.loads(req.data)["properties"]
        return FakeResponse({})
    raise AssertionError(f"unexpected request: {method} {url}")

with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
    ns.main()

os.remove(evt_path)
props = captured.get("patch_props")
if props is None:
    print("    no PATCH was ever sent", file=sys.stderr)
    sys.exit(1)
leaked = [k for k in ("Title", "Opened", "GH Labels") if k in props]
if leaked:
    print(f"    issue-owned fields leaked into a PR-triggered PATCH: {leaked}", file=sys.stderr)
    print(f"    full properties sent: {props}", file=sys.stderr)
sys.exit(0 if not leaked else 1)
PY
check "PR patch on an existing row never sends Title/Opened/GH Labels" 0 $?

# 3a-sanity: the same PATCH must still carry the fields a PR event DOES own.
python3 - "$SCRIPTS" <<'PY'
import sys, os, json
from unittest import mock

sys.path.insert(0, sys.argv[1])
os.environ.update({"NOTION_TOKEN": "t", "NOTION_WORK_DB": "w",
                    "GITHUB_REPOSITORY": "f4d/test-repo", "GITHUB_TOKEN": "g"})
import notion_sync as ns

event = {"pull_request": {
    "number": 45, "title": "x", "body": "Closes #12",
    "html_url": "https://github.com/f4d/test-repo/pull/45",
    "created_at": "2026-01-01T00:00:00Z", "state": "open", "merged": False,
    "head": {"ref": "fix/pr-title-mismatch"}, "labels": [],
}}
evt_path = "/tmp/notion_sync_test_event_3a_sanity.json"
json.dump(event, open(evt_path, "w"))
os.environ["GITHUB_EVENT_PATH"] = evt_path

captured = {}

class FakeResponse:
    def __init__(self, payload):
        self._body = json.dumps(payload).encode()
    def read(self):
        return self._body
    def __enter__(self): return self
    def __exit__(self, *a): return False

def fake_urlopen(req, timeout=None):
    url, method = req.full_url, req.get_method()
    if url.endswith("/query"):
        return FakeResponse({"results": [{"id": "row-12-existing"}]})
    if "/pages/row-12-existing" in url and method == "PATCH":
        captured["patch_props"] = json.loads(req.data)["properties"]
        return FakeResponse({})
    raise AssertionError(f"unexpected request: {method} {url}")

with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
    ns.main()
os.remove(evt_path)

props = captured.get("patch_props", {})
needed = {"State", "PR URL", "Branch", "Synced"}
missing = needed - props.keys()
state_ok = props.get("State", {}).get("select", {}).get("name") == "In Review"
sys.exit(0 if (not missing and state_ok) else 1)
PY
check "...but still updates State/PR URL/Branch/Synced" 0 $?

# 3b. Issue #34 has no Notion row yet. The PR that references it has a
# different title than the real issue. The new row must seed Title from the
# fetched issue, never from the PR.
python3 - "$SCRIPTS" <<'PY'
import sys, os, json
from unittest import mock

sys.path.insert(0, sys.argv[1])
os.environ.update({"NOTION_TOKEN": "t", "NOTION_WORK_DB": "w",
                    "GITHUB_REPOSITORY": "f4d/test-repo", "GITHUB_TOKEN": "g"})
import notion_sync as ns

event = {"pull_request": {
    "number": 46,
    "title": "PR-side title for new issue (must not become the row Title)",
    "body": "Fixes #34",
    "html_url": "https://github.com/f4d/test-repo/pull/46",
    "created_at": "2026-01-02T00:00:00Z", "state": "open", "merged": False,
    "head": {"ref": "feat/x"}, "labels": [{"name": "pr-only-label"}],
}}
evt_path = "/tmp/notion_sync_test_event_3b.json"
json.dump(event, open(evt_path, "w"))
os.environ["GITHUB_EVENT_PATH"] = evt_path

REAL_ISSUE = {
    "number": 34, "title": "Real GitHub Issue Title",
    "html_url": "https://github.com/f4d/test-repo/issues/34",
    "created_at": "2025-12-01T00:00:00Z", "state": "open",
    "labels": [{"name": "bug"}],
}
captured = {}

class FakeResponse:
    def __init__(self, payload):
        self._body = json.dumps(payload).encode()
    def read(self): return self._body
    def __enter__(self): return self
    def __exit__(self, *a): return False

def fake_urlopen(req, timeout=None):
    url, method = req.full_url, req.get_method()
    if "api.github.com" in url:
        assert "34" in url, f"fetched the wrong issue number: {url}"
        return FakeResponse(REAL_ISSUE)
    if url.endswith("/query"):
        return FakeResponse({"results": []})
    if url.endswith("/pages") and method == "POST":
        captured["create_props"] = json.loads(req.data)["properties"]
        return FakeResponse({})
    raise AssertionError(f"unexpected request: {method} {url}")

with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
    ns.main()
os.remove(evt_path)

props = captured.get("create_props")
if props is None:
    print("    no create (POST /pages) was ever sent", file=sys.stderr)
    sys.exit(1)
title = props.get("Title", {}).get("title", [{}])[0].get("text", {}).get("content")
if title != REAL_ISSUE["title"]:
    print(f"    Title={title!r}, want {REAL_ISSUE['title']!r} (fabricated from the PR instead of fetched)", file=sys.stderr)
sys.exit(0 if title == REAL_ISSUE["title"] else 1)
PY
check "seeding a new row from a PR fetches the real issue title, never the PR's" 0 $?

# 3c. Issue #999 has no Notion row, and does not actually exist on GitHub
# (404). Must skip cleanly: no fabricated row, no crash.
python3 - "$SCRIPTS" <<'PY'
import sys, os, json, io, urllib.error
from unittest import mock

sys.path.insert(0, sys.argv[1])
os.environ.update({"NOTION_TOKEN": "t", "NOTION_WORK_DB": "w",
                    "GITHUB_REPOSITORY": "f4d/test-repo", "GITHUB_TOKEN": "g"})
import notion_sync as ns

event = {"pull_request": {
    "number": 47, "title": "orphan reference", "body": "Closes #999",
    "html_url": "https://github.com/f4d/test-repo/pull/47",
    "created_at": "2026-01-03T00:00:00Z", "state": "open", "merged": False,
    "head": {"ref": "chore/x"}, "labels": [],
}}
evt_path = "/tmp/notion_sync_test_event_3c.json"
json.dump(event, open(evt_path, "w"))
os.environ["GITHUB_EVENT_PATH"] = evt_path

create_called = {"value": False}

class FakeResponse:
    def __init__(self, payload):
        self._body = json.dumps(payload).encode()
    def read(self): return self._body
    def __enter__(self): return self
    def __exit__(self, *a): return False

def fake_urlopen(req, timeout=None):
    url, method = req.full_url, req.get_method()
    if "api.github.com" in url:
        raise urllib.error.HTTPError(url, 404, "Not Found", {}, io.BytesIO(b"{}"))
    if url.endswith("/query"):
        return FakeResponse({"results": []})
    if url.endswith("/pages") and method == "POST":
        create_called["value"] = True
        return FakeResponse({})
    raise AssertionError(f"unexpected request: {method} {url}")

with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
    ns.main()  # must not raise
os.remove(evt_path)
sys.exit(1 if create_called["value"] else 0)
PY
check "unresolvable issue reference skips cleanly (no fabricated row, no crash)" 0 $?

echo
echo "Finding 5 — scripts/notion_sync.py: call() must not block forever"

python3 - "$SCRIPTS" <<'PY'
import sys, os
from unittest import mock

sys.path.insert(0, sys.argv[1])
os.environ.update({"NOTION_TOKEN": "t", "NOTION_WORK_DB": "w",
                    "GITHUB_REPOSITORY": "f4d/test-repo", "GITHUB_TOKEN": "g"})
import notion_sync as ns

class FakeResponse:
    def read(self): return b"{}"
    def __enter__(self): return self
    def __exit__(self, *a): return False

seen = {}
def fake_urlopen(req, timeout=None):
    seen["timeout"] = timeout
    return FakeResponse()

with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
    ns.call("GET", "/x")

got = seen.get("timeout")
if not (isinstance(got, (int, float)) and got > 0):
    print(f"    urlopen() was called with timeout={got!r} (no bound — a stall hangs the job)", file=sys.stderr)
sys.exit(0 if (isinstance(got, (int, float)) and got > 0) else 1)
PY
check "call() passes a positive timeout to urlopen()" 0 $?

# fetch_issue() is the second urlopen() call site this fix added (GitHub, not
# Notion) — asserted directly rather than trusting that main()'s end-to-end
# mocks in the Finding 3 checks above happen to exercise it (they accept any
# timeout value, including None, without asserting on it).
python3 - "$SCRIPTS" <<'PY'
import sys, os
from unittest import mock

sys.path.insert(0, sys.argv[1])
os.environ.update({"NOTION_TOKEN": "t", "NOTION_WORK_DB": "w",
                    "GITHUB_REPOSITORY": "f4d/test-repo", "GITHUB_TOKEN": "g"})
import notion_sync as ns

class FakeResponse:
    def read(self): return b'{"number": 1, "title": "x"}'
    def __enter__(self): return self
    def __exit__(self, *a): return False

seen = {}
def fake_urlopen(req, timeout=None):
    seen["timeout"] = timeout
    return FakeResponse()

with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
    ns.fetch_issue(1)

got = seen.get("timeout")
if not (isinstance(got, (int, float)) and got > 0):
    print(f"    fetch_issue()'s urlopen() was called with timeout={got!r}", file=sys.stderr)
sys.exit(0 if (isinstance(got, (int, float)) and got > 0) else 1)
PY
check "fetch_issue() passes a positive timeout to urlopen() too" 0 $?

python3 - "$SCRIPTS" <<'PY'
import sys, os
from unittest import mock

sys.path.insert(0, sys.argv[1])
os.environ.update({"NOTION_TOKEN": "t", "NOTION_WORK_DB": "w",
                    "GITHUB_REPOSITORY": "f4d/test-repo", "GITHUB_TOKEN": "g"})
import notion_sync as ns

def fake_urlopen(req, timeout=None):
    raise TimeoutError("simulated stall")

raised = False
with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
    try:
        ns.call("GET", "/x")
    except Exception:
        raised = True
sys.exit(0 if raised else 1)
PY
check "a stalled request still raises (never silently swallowed)" 0 $?

python3 - "$SCRIPTS" <<'PY'
import sys, os, io
from unittest import mock

sys.path.insert(0, sys.argv[1])
os.environ.update({"NOTION_TOKEN": "t", "NOTION_WORK_DB": "w",
                    "GITHUB_REPOSITORY": "f4d/test-repo", "GITHUB_TOKEN": "g"})
import notion_sync as ns

def fake_urlopen(req, timeout=None):
    raise TimeoutError("simulated stall")

buf = io.StringIO()
with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen), \
     mock.patch("sys.stderr", buf):
    try:
        ns.call("GET", "/x")
    except Exception:
        pass
logged = bool(buf.getvalue().strip())
if not logged:
    print("    a timeout produced no stderr diagnostic (HTTPError gets one; this didn't)", file=sys.stderr)
sys.exit(0 if logged else 1)
PY
check "a stalled request is logged the same way an HTTPError is (log then raise)" 0 $?

echo
echo "OWNED-set accuracy"
python3 - "$SCRIPTS" <<'PY'
import sys, os
sys.path.insert(0, sys.argv[1])
os.environ.update({"NOTION_TOKEN": "t", "NOTION_WORK_DB": "w",
                    "GITHUB_REPOSITORY": "f4d/test-repo", "GITHUB_TOKEN": "g"})
import notion_sync as ns
# build_props always writes Title for a real issue event; OWNED claims to
# be "the only fields the sync ever writes" but omitted it.
sys.exit(0 if "Title" in ns.OWNED else 1)
PY
check "OWNED includes Title (build_props writes it on every real issue event)" 0 $?

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
