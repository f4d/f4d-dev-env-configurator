#!/usr/bin/env python3
"""
I-02 / I-03 / G-05 — adapter fixture health.

Stale fixtures are the failure that looks most like data and least like a defect:
a vendor changes a field, the fixture keeps passing, production breaks.

Checks:
  I-02  every adapter has happy / empty / rate-limited / malformed fixtures
  I-03  every fixture carries recorded_at, and none is older than MAX_AGE_DAYS
  G-05  a fixture edit has not deleted a case it previously expressed

Exit 1 on any failure. Wire into CI.
"""
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone

MAX_AGE_DAYS = int(os.environ.get("FIXTURE_MAX_AGE_DAYS", "90"))
REQUIRED = {"happy", "empty", "rate_limited", "malformed"}
FIXTURE_DIRS = ("fixtures", "__fixtures__", "testdata", "cassettes")


sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import SKIP_DIRS, filter_skipped_paths, repo_root as root  # noqa: E402


def find_fixture_dirs(base):
    out = []
    for dirpath, dirnames, _ in os.walk(base):
        # A21: this used to be `if any(p in dirpath ...)` — a substring match
        # against a 4-item hand-rolled list that excluded neither build/ nor
        # .next/, and never pruned dirnames, so the walk still descended into
        # every skipped directory looking for nested fixture dirs. Prune for
        # real, from the shared set, same as every other scanner.
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
        for d in dirnames:
            if d in FIXTURE_DIRS:
                out.append(os.path.join(dirpath, d))
    return out


def main():
    base = root()
    dirs = find_fixture_dirs(base)
    if not dirs:
        print("No fixture directories found — nothing to check.")
        print("If this project has adapters, that itself is the finding (I-02).")
        return 0

    failures = []
    cutoff = datetime.now(timezone.utc) - timedelta(days=MAX_AGE_DAYS)

    for fdir in dirs:
        adapter = os.path.basename(os.path.dirname(fdir))
        names, recorded = set(), {}

        for fn in os.listdir(fdir):
            if not fn.endswith(".json"):
                continue
            stem = os.path.splitext(fn)[0].lower().replace("-", "_")
            names.add(stem)
            path = os.path.join(fdir, fn)
            try:
                data = json.load(open(path))
            except Exception as e:
                failures.append(f"{path}: unparseable ({e})")
                continue
            meta = data.get("_meta", {}) if isinstance(data, dict) else {}
            ts = meta.get("recorded_at")
            if not ts:
                failures.append(
                    f"{path}: missing _meta.recorded_at (I-03). "
                    f'Add {{"_meta": {{"recorded_at": "YYYY-MM-DDTHH:MM:SSZ", "source": "..."}}}}'
                )
                continue
            try:
                when = datetime.fromisoformat(ts.replace("Z", "+00:00"))
            except Exception:
                failures.append(f"{path}: recorded_at is not ISO-8601 ({ts})")
                continue
            recorded[fn] = when
            if when < cutoff:
                age = (datetime.now(timezone.utc) - when).days
                failures.append(
                    f"{path}: recorded {age}d ago, limit {MAX_AGE_DAYS}d (I-03). "
                    f"Re-record against the live API and diff the shape."
                )

        missing = REQUIRED - {n for n in names for r in REQUIRED if r in n}
        if missing:
            failures.append(
                f"{fdir}: adapter '{adapter}' missing fixtures for {sorted(missing)} (I-02)"
            )

    failures += g05_case_diff(dirs)

    if failures:
        print("FIXTURE CHECK FAILED\n")
        for f in failures:
            print(f"  {f}")
        print(f"\n{len(failures)} problem(s). See rules S-* / I-* in REGISTRY.md.")
        return 1

    print(f"Fixture check passed — {len(dirs)} adapter fixture dir(s), all fresh.")
    return 0


def case_count(data):
    """Cases a fixture expresses: top-level keys (minus _meta) or array length."""
    if isinstance(data, dict):
        return len([k for k in data if k != "_meta"])
    if isinstance(data, list):
        return len(data)
    return 1


def g05_case_diff(dirs):
    """G-05 — improving a fixture must not delete a case it expressed.

    Compares each fixture's case count against $BASE_REF. A decrease needs
    `fixture-case-removed-ok: <reason>` in the PR body — correcting a fake can
    silently remove the only case expressing a residual. Without BASE_REF
    (local run) this states so and skips; CI always sets it.
    """
    base = os.environ.get("BASE_REF", "").strip()
    if not base:
        print("check_fixtures: NOTE — BASE_REF unset; G-05 case-diff runs in CI only.")
        return []
    body = os.environ.get("PR_BODY", "")
    waiver = __import__("re").search(r"fixture-case-removed-ok:\s*(\S.*)", body)
    problems = []
    # Baseline fixtures DELETED from the worktree are the strongest case
    # removal of all — enumerate the base's fixture paths, not just survivors.
    re_mod = __import__("re")
    try:
        base_files = subprocess.run(["git", "ls-tree", "-r", "--name-only", base],
                                    capture_output=True, text=True, check=True).stdout.splitlines()
    except subprocess.CalledProcessError:
        base_files = []
    # Agree with find_fixture_dirs()'s SKIP_DIRS/dot-dir walk pruning, or a
    # fixture that lived under a directory this run declares out of scope
    # (e.g. a dot-prefixed vendor cache) still reads as a G-05 case-removal
    # when its directory disappears — a false positive on a path nothing
    # above this ever considered in scope.
    base_files = filter_skipped_paths(base_files)
    fixture_seg = re_mod.compile(r"(^|/)(fixtures|__fixtures__|testdata|cassettes)(/|$)")
    for bf in base_files:
        if not bf.endswith(".json") or not fixture_seg.search(bf):
            continue
        if not os.path.exists(bf):
            if waiver:
                print(f"check_fixtures: {bf} deleted, ACCEPTED: {waiver.group(1).strip()[:100]} (G-05)")
            else:
                problems.append(
                    f"{bf}: fixture file deleted outright (G-05) — every case it expressed is gone. "
                    "State `fixture-case-removed-ok: <reason>` in the PR body if this is genuinely right."
                )
    for fdir in dirs:
        for fn in os.listdir(fdir):
            if not fn.endswith(".json"):
                continue
            path = os.path.join(fdir, fn)
            try:
                now = case_count(json.load(open(path)))
            except Exception:
                continue  # unparseable already failed I-03 above
            try:
                old_blob = subprocess.run(["git", "show", f"{base}:{os.path.relpath(path)}"],
                                          capture_output=True, text=True, check=True).stdout
                before = case_count(json.loads(old_blob))
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                continue  # new fixture, or old was unparseable — nothing to protect
            if now < before:
                if waiver:
                    print(f"check_fixtures: {path} cases {before} -> {now}, ACCEPTED: {waiver.group(1).strip()[:100]} (G-05)")
                else:
                    problems.append(
                        f"{path}: fixture case count decreased {before} -> {now} (G-05). "
                        "Diff the cases it expressed, not just its values — or state "
                        "`fixture-case-removed-ok: <reason>` in the PR body."
                    )
    return problems


if __name__ == "__main__":
    sys.exit(main())
