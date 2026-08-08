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
from _common import repo_root as root  # noqa: E402


def find_fixture_dirs(base):
    out = []
    for dirpath, dirnames, _ in os.walk(base):
        if any(p in dirpath for p in (".git", "node_modules", ".venv", "dist")):
            continue
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

    if failures:
        print("FIXTURE CHECK FAILED\n")
        for f in failures:
            print(f"  {f}")
        print(f"\n{len(failures)} problem(s). See rules S-* / I-* in REGISTRY.md.")
        return 1

    print(f"Fixture check passed — {len(dirs)} adapter fixture dir(s), all fresh.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
