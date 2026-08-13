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
#
# 2026-08-13 follow-up (PR #36 review + roofadvisor/GHL-MCP PR #1075): two
# more findings on this same file, added below rather than in a new file.
# The "Finding 2" section's repo-wide concurrency key is itself superseded
# here — it fixed the original race but introduced a different one (see
# docs/BACKLOG.md A22 addendum) — so those checks now assert the corrected,
# per-linked-issue architecture instead of the repo-wide key they used to
# assert. The keyword-vocabulary checks are new additions alongside it.
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
echo "Finding 2 — notion-sync.yml: shared concurrency key (2026-08-13: now per-linked-issue, not repo-wide)"
# The repo-wide key this used to assert traded the original race (a PR and
# the issue it closes carrying different keys) for a different, real bug:
# GitHub cancels a concurrency group's existing PENDING run the instant a
# new one is queued behind it — "any existing pending job or workflow in the
# same concurrency group will be canceled and the new queued job or workflow
# will take its place" — regardless of cancel-in-progress, which only
# additionally governs the currently RUNNING one (docs.github.com/en/actions/
# writing-workflows/choosing-what-your-workflow-does/control-the-concurrency-
# of-workflows-and-jobs). Under a repo-wide key, an event for unrelated issue
# B could cancel issue A's still-pending sync with nothing left to retry A.
# Fixed by keying on the *linked issue* instead (resolved in a dedicated
# `resolve` job — a concurrency `group:` expression is evaluated before any
# job runs, from the raw event payload, using GitHub's expression syntax; it
# cannot itself regex-parse a PR body) so a PR and the issue it closes share
# a group and serialize, while two unrelated issues get distinct groups and
# run in parallel.
python3 - "$KIT/templates/github/notion-sync.yml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
ok = "concurrency" not in doc
if not ok:
    print(f"    top-level concurrency block still present: {doc.get('concurrency')!r}", file=sys.stderr)
sys.exit(0 if ok else 1)
PY
check "no top-level (workflow-level) concurrency block" 0 $?

python3 - "$KIT/templates/github/notion-sync.yml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
jobs = doc["jobs"]
ok = "resolve" in jobs and "concurrency" not in jobs["resolve"]
if not ok:
    print(f"    jobs={list(jobs)!r} resolve.concurrency={jobs.get('resolve', {}).get('concurrency')!r}", file=sys.stderr)
sys.exit(0 if ok else 1)
PY
check "resolve job exists and carries no concurrency block of its own" 0 $?

python3 - "$KIT/templates/github/notion-sync.yml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
outputs = doc["jobs"]["resolve"].get("outputs", {})
ok = outputs.get("issue_number") == "${{ steps.resolve.outputs.issue_number }}"
if not ok:
    print(f"    resolve.outputs={outputs!r}", file=sys.stderr)
sys.exit(0 if ok else 1)
PY
check "resolve job declares issue_number as a job output sourced from its own step" 0 $?

python3 - "$KIT/templates/github/notion-sync.yml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
sync = doc["jobs"]["sync"]
ok = sync.get("needs") == "resolve"
if not ok:
    print(f"    sync.needs={sync.get('needs')!r}", file=sys.stderr)
sys.exit(0 if ok else 1)
PY
check "sync job declares needs: resolve" 0 $?

python3 - "$KIT/templates/github/notion-sync.yml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
sync = doc["jobs"]["sync"]
concurrency = sync.get("concurrency", {})
group = concurrency.get("group", "")
cip = concurrency.get("cancel-in-progress")
keyed_on_output = "needs.resolve.outputs.issue_number" in group
repo_keyed = "github.repository" in group
# The pre-A22 bug: keying on the *event's own* number lets a PR and the
# issue it closes carry different keys and race. Must never regress to this.
per_event_keyed = "github.event.issue.number" in group or "github.event.pull_request.number" in group
ok = keyed_on_output and repo_keyed and not per_event_keyed and cip is False
if not ok:
    print(f"    sync.concurrency={concurrency!r}", file=sys.stderr)
sys.exit(0 if ok else 1)
PY
check "sync job's concurrency (job-level, so it can see the needs context) keys on the resolved linked issue" 0 $?

echo
echo "Finding 2 follow-up (concrete example) — PR #50 closing issue #20, vs. unrelated issue #99"
# Reproduces the roofadvisor/GHL-MCP PR #1075 reviewer's own example: PR #50
# whose body closes #20, and the issues.closed event GitHub fires when #20
# is actually closed as a result. Runs the ACTUAL resolve-issue subprocess
# the workflow's resolve job invokes (not a stub), with only
# GITHUB_EVENT_PATH set, and proves both resolve to the identical
# concurrency-group string while an unrelated issue #99 resolves to a
# different one.
python3 - "$SCRIPTS" <<'PY'
import json, os, subprocess, sys

script = os.path.join(sys.argv[1], "notion_sync.py")
EVT = "/tmp/notion_sync_test_resolve_concrete.json"


def resolve(event):
    json.dump(event, open(EVT, "w"))
    env = {"PATH": os.environ.get("PATH", ""), "GITHUB_EVENT_PATH": EVT}
    try:
        return subprocess.run([sys.executable, script, "resolve-issue"],
                               env=env, capture_output=True, text=True, timeout=10)
    finally:
        os.remove(EVT)


def group_for(number_output, repo="roofadvisor/GHL-MCP"):
    return f"notion-sync-{repo}-{number_output}"


issue_20_closed = {"action": "closed", "issue": {"number": 20}}
pr_50_closed = {"action": "closed", "pull_request": {
    "number": 50, "body": "This closes #20 by adding the missing null check.",
}}
issue_99_labeled = {"action": "labeled", "issue": {"number": 99}}

r_issue, r_pr, r_other = resolve(issue_20_closed), resolve(pr_50_closed), resolve(issue_99_labeled)

errors = []
for label, r in (("issues(#20)", r_issue), ("pull_request(#50)", r_pr), ("issues(#99)", r_other)):
    if r.returncode != 0:
        errors.append(f"{label} exited {r.returncode}: {r.stderr!r}")

n_issue, n_pr, n_other = r_issue.stdout.strip(), r_pr.stdout.strip(), r_other.stdout.strip()
group_issue, group_pr, group_other = group_for(n_issue), group_for(n_pr), group_for(n_other)

if group_issue != group_pr:
    errors.append(f"same-row groups differ: issues(#20)={group_issue!r} pull_request(#50)={group_pr!r}")
if group_issue == group_other:
    errors.append(f"unrelated issue collided: {group_issue!r} == {group_other!r}")

if errors:
    for e in errors:
        print(f"    {e}", file=sys.stderr)
    print(f"    resolved: issues(#20)->{n_issue!r} pull_request(#50)->{n_pr!r} issues(#99)->{n_other!r}", file=sys.stderr)

sys.exit(1 if errors else 0)
PY
check "issues#20 and pull_request#50(closes #20) resolve to the SAME group; unrelated issue#99 does not" 0 $?

echo
echo "Finding 1 follow-up — scripts/notion_sync.py: resolve-issue CLI mode (used by the workflow's resolve job)"
python3 - "$SCRIPTS" <<'PY'
import json, os, subprocess, sys

script = os.path.join(sys.argv[1], "notion_sync.py")
EVT = "/tmp/notion_sync_test_resolve_secretfree.json"
json.dump({"issue": {"number": 42}}, open(EVT, "w"))
# Deliberately NOT set: NOTION_TOKEN, NOTION_WORK_DB, GITHUB_TOKEN. The
# resolve job in the workflow never has them — if this mode required any of
# them, the job computing the concurrency key would need secrets it has no
# other reason to hold.
env = {"PATH": os.environ.get("PATH", ""), "GITHUB_EVENT_PATH": EVT}
try:
    out = subprocess.run([sys.executable, script, "resolve-issue"],
                          env=env, capture_output=True, text=True, timeout=10)
finally:
    os.remove(EVT)

ok = out.returncode == 0 and out.stdout.strip() == "42"
if not ok:
    print(f"    exit={out.returncode} stdout={out.stdout!r} stderr={out.stderr!r}", file=sys.stderr)
sys.exit(0 if ok else 1)
PY
check "resolve-issue works with ONLY GITHUB_EVENT_PATH set (no Notion/GitHub secrets)" 0 $?

python3 - "$SCRIPTS" <<'PY'
import json, os, subprocess, sys

script = os.path.join(sys.argv[1], "notion_sync.py")
EVT = "/tmp/notion_sync_test_resolve_prkeyword.json"
# "Fix #123" — one of the six keywords Finding 2 (regex) added. Proves that
# fix through the actual CLI invocation the workflow makes, not just the
# parse_linked_issue() unit tests below.
json.dump({"pull_request": {"number": 77, "body": "Fix #123 once and for all."}}, open(EVT, "w"))
env = {"PATH": os.environ.get("PATH", ""), "GITHUB_EVENT_PATH": EVT}
try:
    out = subprocess.run([sys.executable, script, "resolve-issue"],
                          env=env, capture_output=True, text=True, timeout=10)
finally:
    os.remove(EVT)

ok = out.returncode == 0 and out.stdout.strip() == "123"
if not ok:
    print(f"    exit={out.returncode} stdout={out.stdout!r} stderr={out.stderr!r}", file=sys.stderr)
sys.exit(0 if ok else 1)
PY
check "resolve-issue recognizes a previously-unsupported keyword ('Fix #N') too" 0 $?

python3 - "$SCRIPTS" <<'PY'
import json, os, subprocess, sys

script = os.path.join(sys.argv[1], "notion_sync.py")
EVT = "/tmp/notion_sync_test_resolve_unlinked.json"
json.dump({"pull_request": {"number": 61, "body": "No linked issue here."}}, open(EVT, "w"))
env = {"PATH": os.environ.get("PATH", ""), "GITHUB_EVENT_PATH": EVT}
try:
    out = subprocess.run([sys.executable, script, "resolve-issue"],
                          env=env, capture_output=True, text=True, timeout=10)
finally:
    os.remove(EVT)

# Empty stdout + exit 0: an unresolvable PR is a normal outcome, not a
# failure. The workflow step tells the two apart by checking for empty
# output, so a nonzero exit here would wrongly fail the resolve job.
ok = out.returncode == 0 and out.stdout.strip() == ""
if not ok:
    print(f"    exit={out.returncode} stdout={out.stdout!r} stderr={out.stderr!r}", file=sys.stderr)
sys.exit(0 if ok else 1)
PY
check "resolve-issue exits 0 with empty stdout when no issue is linked (not a failure)" 0 $?

echo
echo "Finding 2 follow-up — scripts/notion_sync.py: full closing-keyword vocabulary"
# Pre-fix, only closes|fixes|resolves matched (present-tense plural only).
# GitHub also recognizes close, closed, fix, fixed, resolve, resolved — 9
# keywords total, case-insensitive. A PR body written as "Fix #123" (a valid
# GitHub closing reference) found no match, so the PR-linked sync path
# exited early ("PR has no linked issue"), leaving the linked issue's row
# never updated with the PR URL/branch/commit/merged state.
python3 - "$SCRIPTS" <<'PY'
import sys, os
sys.path.insert(0, sys.argv[1])
os.environ.update({"NOTION_TOKEN": "t", "NOTION_WORK_DB": "w",
                    "GITHUB_REPOSITORY": "f4d/test-repo", "GITHUB_TOKEN": "g"})
import notion_sync as ns

cases = [
    ("close #1", 1), ("closes #2", 2), ("closed #3", 3),
    ("fix #4", 4), ("fixes #5", 5), ("fixed #6", 6),
    ("resolve #7", 7), ("resolves #8", 8), ("resolved #9", 9),
]
bad = [(b, ns.parse_linked_issue(b), w) for b, w in cases if ns.parse_linked_issue(b) != w]
if bad:
    for b, got, want in bad:
        print(f"    body={b!r} got={got!r} want={want!r}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY
check "all 9 GitHub closing keywords match" 0 $?

python3 - "$SCRIPTS" <<'PY'
import sys, os
sys.path.insert(0, sys.argv[1])
os.environ.update({"NOTION_TOKEN": "t", "NOTION_WORK_DB": "w",
                    "GITHUB_REPOSITORY": "f4d/test-repo", "GITHUB_TOKEN": "g"})
import notion_sync as ns

cases = [
    ("Close #1", 1), ("Closes #2", 2), ("Closed #3", 3),
    ("FIX #4", 4), ("FIXES #5", 5), ("FIXED #6", 6),
    ("Resolve #7", 7), ("Resolves #8", 8), ("RESOLVED #9", 9),
]
bad = [(b, ns.parse_linked_issue(b), w) for b, w in cases if ns.parse_linked_issue(b) != w]
if bad:
    for b, got, want in bad:
        print(f"    body={b!r} got={got!r} want={want!r}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY
check "all 9 keywords match case-insensitively" 0 $?

python3 - "$SCRIPTS" <<'PY'
import sys, os
sys.path.insert(0, sys.argv[1])
os.environ.update({"NOTION_TOKEN": "t", "NOTION_WORK_DB": "w",
                    "GITHUB_REPOSITORY": "f4d/test-repo", "GITHUB_TOKEN": "g"})
import notion_sync as ns

# Words that merely CONTAIN a keyword as a substring must not false-match:
# a suffix ("unresolved" ends in "resolved"), a prefix-glued word
# ("prefixes" contains "fixes"), and trailing text glued to the keyword
# itself ("closest" starts with "close" but is not followed by whitespace).
negatives = [
    "unresolved #123 still open",
    "prefixes #99 are weird",
    "closest #1 to done",
    "enclosed #5 in the box",
    "See #123 for context",  # no keyword at all
    "",
    None,
]
bad = [(b, ns.parse_linked_issue(b)) for b in negatives if ns.parse_linked_issue(b) is not None]
if bad:
    for b, got in bad:
        print(f"    false positive on body={b!r} -> {got!r}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY
check "keyword-shaped substrings inside other words, and bodies with no keyword, do not match" 0 $?

echo
echo "Finding 2 follow-up (end-to-end) — main(): a PR using a previously-unsupported keyword now syncs"
# Direct regression for the roofadvisor/GHL-MCP PR #1075 reviewer's exact
# complaint: "the workflow exits without recording the PR URL, branch,
# commit, or merged state, leaving the linked issue represented only as
# Closed." Body says "Resolved #12" — pre-fix, no keyword matched, main()
# printed "PR has no linked issue" and returned without ever calling Notion.
python3 - "$SCRIPTS" <<'PY'
import sys, os, json
from unittest import mock

sys.path.insert(0, sys.argv[1])
os.environ.update({"NOTION_TOKEN": "t", "NOTION_WORK_DB": "w",
                    "GITHUB_REPOSITORY": "f4d/test-repo", "GITHUB_TOKEN": "g"})
import notion_sync as ns

event = {"pull_request": {
    "number": 90, "title": "x", "body": "Resolved #12",
    "html_url": "https://github.com/f4d/test-repo/pull/90",
    "created_at": "2026-01-01T00:00:00Z", "state": "closed", "merged": True,
    "merged_at": "2026-01-05T00:00:00Z", "merge_commit_sha": "deadbeef1234",
    "head": {"ref": "fix/x"}, "labels": [],
}}
evt_path = "/tmp/notion_sync_test_event_regex_followup.json"
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

props = captured.get("patch_props")
if props is None:
    print("    no PATCH was ever sent — 'Resolved #12' was not recognized as a linked issue", file=sys.stderr)
    sys.exit(1)
state_ok = props.get("State", {}).get("select", {}).get("name") == "Merged"
if not state_ok:
    print(f"    patch_props={props}", file=sys.stderr)
sys.exit(0 if state_ok else 1)
PY
check "PR body 'Resolved #12' (previously unsupported) now updates the linked issue's row" 0 $?

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
