#!/usr/bin/env python3
"""
Reads .claude/.session-log and answers, with counts rather than recollection:
  - How many sessions started outside the repo root (rules would not have loaded)
  - Whether the rules count has been stable
  - How often verify actually ran

This exists because "observe for a week and then decide" is not something an
agent can do. Every session starts blank. The observation has to be written down.
"""
import os
import subprocess
import sys
from collections import Counter


sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import repo_root  # noqa: E402


def main():
    root = repo_root()
    path = os.path.join(root, ".claude", ".session-log")
    if not os.path.exists(path):
        print("No session log yet.")
        print("Wire hooks/session-context.sh, then re-run after a few sessions.")
        return 0

    starts, verifies, dirs, rulecounts = [], 0, Counter(), Counter()
    for line in open(path):
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 2 and parts[1] == "verify":
            verifies += 1
        elif len(parts) >= 5:
            starts.append(parts)
            dirs[parts[2] or "(root)"] += 1
            rulecounts[parts[4]] += 1

    n = len(starts)
    if n == 0:
        print("Session log exists but records no session starts.")
        return 0

    sub = sum(1 for s in starts if s[1] == "subdir")
    nomd = sum(1 for s in starts if s[3] == "no-claudemd")

    print(f"SESSIONS RECORDED   {n}")
    print(f"  from repo root    {n - sub}")
    print(f"  from a subdir     {sub}  ({sub * 100 // n}%)")
    print(f"VERIFY RUNS         {verifies}   ({verifies / n:.1f} per session)")
    print()

    if sub:
        print(f"FINDING: {sub} of {n} sessions started outside the repo root.")
        print("Without the SessionStart hook those sessions loaded NO repo rules.")
        print("Any earlier conclusion that 'the rules were ignored' is unreliable")
        print("for those sessions — the rules were never in context.")
        print("Top start directories:")
        for d, c in dirs.most_common(5):
            print(f"  {c:>4}  {d}")
        print()

    if nomd:
        print(f"FINDING: {nomd} sessions ran with no CLAUDE.md at the repo root.")
        print()

    if len(rulecounts) > 1:
        print("FINDING: rules count changed across sessions —", dict(rulecounts))
        print("Rules were added or removed mid-stream; comparisons across the")
        print("window are not like-for-like.")
        print()

    if verifies < n * 0.5:
        print("FINDING: verify ran in fewer than half of sessions.")
        print("Any 'done' claim from a session without a verify run was a guess.")
        print()

    print("DECIDE NOW, NOT LATER")
    if sub == 0 and n >= 5:
        print("  Rules loaded in every recorded session. If a rule still did not")
        print("  fire, it is genuinely mis-classified: promote it to a hook or a test.")
    elif sub:
        print("  Load path was broken for some sessions. Fix it first, then")
        print("  re-read this report before promoting any rule to a test.")
    else:
        print(f"  Only {n} sessions recorded. Thin, but do not wait passively —")
        print("  run /project-audit now and use the static evidence instead.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
