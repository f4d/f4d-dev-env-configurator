#!/usr/bin/env python3
"""
C-08 — never delete a test to make a build pass.

Compares the number of test cases on this branch against $BASE_REF. A decrease
fails the gate unless the PR body carries `test-removal-ok: <reason>` — moving
or refactoring tests is fine (count is repo-wide, not per-file); making red
tests disappear is not.

Counted as tests: `def test_` (python), `it(`/`test(` call sites (js/ts) in
test-shaped files (*_test.*, *.test.*, *.spec.*, test_*.py, files under tests/).

Without $BASE_REF there is no baseline to compare — the gate states that and
passes (CI always sets it; a local run is not the enforcement point).
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import SKIP_DIRS, filter_skipped_paths  # noqa: E402

TEST_FILE = re.compile(r"(^|/)tests?/|(^|/)test_[^/]+\.py$|[._][a-z]*test[a-z]*\.[jt]sx?$|\.spec\.[jt]sx?$|_test\.py$", re.I)
CASE = re.compile(r"^\s*(?:async\s+)?def test_|(?<![.\w])(?:it|test)\s*\(", re.M)


def count_at(ref):
    try:
        files = subprocess.run(["git", "ls-tree", "-r", "--name-only", ref],
                               capture_output=True, text=True, check=True).stdout.splitlines()
    except subprocess.CalledProcessError as e:
        print(f"check_test_count: ERROR: cannot list {ref}: {e.stderr.strip()} (C-08)")
        sys.exit(1)
    # Agree with count_worktree()'s SKIP_DIRS/dot-dir walk pruning, or a
    # tracked test file that just became skipped (e.g. under a newly
    # dot-prefixed or SKIP_DIRS directory) reads as a baseline-only test and
    # reports a false C-08 regression on an otherwise-unchanged PR.
    files = filter_skipped_paths(files)
    total = 0
    for f in files:
        if not TEST_FILE.search(f):
            continue
        try:
            blob = subprocess.run(["git", "show", f"{ref}:{f}"], capture_output=True, text=True, check=True).stdout
        except subprocess.CalledProcessError:
            continue
        total += len(CASE.findall(blob))
    return total


def count_worktree():
    total = 0
    for dirpath, dirnames, filenames in os.walk("."):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
        for name in filenames:
            rel = os.path.relpath(os.path.join(dirpath, name))
            if not TEST_FILE.search(rel.replace(os.sep, "/")):
                continue
            try:
                total += len(CASE.findall(open(rel, encoding="utf-8", errors="replace").read()))
            except OSError:
                continue
    return total


def main():
    base = os.environ.get("BASE_REF", "").strip()
    if not base:
        print("check_test_count: NOTE — BASE_REF unset; no baseline to compare against (C-08 is a CI gate).")
        return 0
    # Compare from the MERGE BASE, not the base tip: tests added to the target
    # branch after this PR branched are not this PR's deletions.
    try:
        mb = subprocess.run(["git", "merge-base", base, "HEAD"],
                            capture_output=True, text=True, check=True).stdout.strip()
    except subprocess.CalledProcessError:
        mb = base
        print(f"check_test_count: NOTE — merge-base with {base} unresolved; comparing against the tip.")
    before, after = count_at(mb), count_worktree()
    if after >= before:
        print(f"check_test_count: OK — tests {before} -> {after} (C-08).")
        return 0
    body = os.environ.get("PR_BODY", "")
    m = re.search(r"test-removal-ok:\s*(\S.*)", body)
    if m:
        print(f"check_test_count: tests {before} -> {after}, ACCEPTED with stated reason: {m.group(1).strip()[:120]} (C-08)")
        return 0
    print(f"C-08 VIOLATION: test count decreased {before} -> {after} against {base}.")
    print("Deleting tests to pass a build is never acceptable silently. If this removal")
    print("is genuinely right (dead feature, superseded suite), state it in the PR body:")
    print("  test-removal-ok: <what was removed and why coverage does not regress>")
    return 1


if __name__ == "__main__":
    sys.exit(main())
