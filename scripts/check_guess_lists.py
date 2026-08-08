#!/usr/bin/env python3
"""
S-05 — one canonical resolver per question.

Two hardcoded lists answering the same question will disagree, and the
disagreement surfaces as a blank rather than a conflict. This finds duplicate
constant collections across modules.

Heuristic and deliberately conservative: flags only near-identical literal
collections of 3+ string members appearing in 2+ files.

Exit 1 on any duplicate. Exit 0 clean.
"""
import os
import re
import subprocess
import sys
from collections import defaultdict

SKIP = (".git", "node_modules", ".venv", "dist", "build", "fixtures", "__fixtures__", "testdata")
EXT = (".py", ".ts", ".tsx", ".js", ".jsx")
LIST_RE = re.compile(r"[\[\(]\s*((?:['\"][A-Za-z0-9_\- ]{2,40}['\"]\s*,\s*){2,}['\"][A-Za-z0-9_\- ]{2,40}['\"])\s*,?\s*[\]\)]")


sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import repo_root as root  # noqa: E402


def main():
    base = root()
    seen = defaultdict(list)

    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in SKIP and not d.startswith(".")]
        for fn in filenames:
            if not fn.endswith(EXT):
                continue
            p = os.path.join(dirpath, fn)
            try:
                text = open(p, errors="ignore").read()
            except Exception:
                continue
            for m in LIST_RE.finditer(text):
                members = tuple(sorted(
                    x.strip("'\"") for x in re.findall(r"['\"]([^'\"]+)['\"]", m.group(1))
                ))
                # CLI argument arrays are not guess lists about domain values.
                if any(x.startswith("-") for x in members):
                    continue
                if len(members) >= 3:
                    rel = os.path.relpath(p, base)
                    if rel not in seen[members]:
                        seen[members].append(rel)

    dupes = {k: v for k, v in seen.items() if len(v) > 1}
    if not dupes:
        print("No duplicate constant lists found (S-05).")
        return 0

    print("DUPLICATE CONSTANT LISTS (S-05)\n")
    print("Two lists answering the same question will disagree, and the")
    print("disagreement shows up as a blank rather than a conflict.\n")
    for members, files in sorted(dupes.items(), key=lambda kv: -len(kv[1])):
        preview = ", ".join(members[:4]) + ("..." if len(members) > 4 else "")
        print(f"  [{preview}]")
        for f in files:
            print(f"      {f}")
        print()
    print("Fix: extract one dependency-free leaf both sides import. Never copy.")
    print("If the source can report these values live, delete the list entirely.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
