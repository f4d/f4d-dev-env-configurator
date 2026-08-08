#!/usr/bin/env python3
"""
K-02 / K-03 — contract version pinning.

A consumer that drifts two majors behind will still compile and still be wrong.
Verifies this repo pins a contract version, and that the pin is not more than one
major behind the contract's current release.

Config, in .claude/contract.json:
  {"package": "@org/contracts", "current": "3.1.0", "max_major_lag": 1}

Exit 1 on failure.
"""
import json
import os
import re
import subprocess
import sys


sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import repo_root as root  # noqa: E402


def find_pin(base, pkg):
    pj = os.path.join(base, "package.json")
    if os.path.exists(pj):
        d = json.load(open(pj))
        for section in ("dependencies", "devDependencies"):
            v = d.get(section, {}).get(pkg)
            if v:
                return v
    for name in ("pyproject.toml", "requirements.txt"):
        p = os.path.join(base, name)
        if os.path.exists(p):
            m = re.search(rf"{re.escape(pkg)}\s*[=~><]+\s*[\"']?([0-9][^\"',\s]*)", open(p).read())
            if m:
                return m.group(1)
    return None


def major(v):
    m = re.search(r"(\d+)", v or "")
    return int(m.group(1)) if m else None


def main():
    base = root()
    cfg_path = os.path.join(base, ".claude", "contract.json")
    if not os.path.exists(cfg_path):
        print("No .claude/contract.json — this repo declares no contract dependency.")
        print("If it consumes a shared contract, that is the finding (K-02).")
        return 0

    cfg = json.load(open(cfg_path))
    pkg = cfg["package"]
    current = cfg.get("current")
    max_lag = int(cfg.get("max_major_lag", 1))

    pin = find_pin(base, pkg)
    if not pin:
        print(f"FAIL (K-02): no pinned version of {pkg} found in this repo.")
        print("Consumers must pin a contract version explicitly.")
        return 1

    pm, cm = major(pin), major(current)
    print(f"contract {pkg}: pinned {pin}, current {current}")

    if pm is None or cm is None:
        print("WARN: could not compare majors. Check the version strings.")
        return 0

    lag = cm - pm
    if lag > max_lag:
        print(f"FAIL (K-03): pinned major {pm} is {lag} behind current {cm} (limit {max_lag}).")
        print("Bump the pin in its own commit, then align the consumers it breaks.")
        return 1

    if lag > 0:
        print(f"OK, but {lag} major behind. Schedule the bump.")
    else:
        print("OK — current.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
