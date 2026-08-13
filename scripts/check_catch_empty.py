#!/usr/bin/env python3
"""
S-03 — the `catch → []` trap.

A catch that returns an empty collection (or null) makes a failure
indistinguishable from an empty result: every downstream "is anything
missing?" gate passes vacuously, and the outage ships as plausible data.
Proven live: a failed pipeline fetch published raw IDs as report rows, a
failed tag fetch drove duplicate tag creation (GHL-MCP audit F3–F5).

Known-idiom exclusion (A16, measured on the GHL-MCP re-audit): request-body
parse guards — `request.json().catch(() => null)` and kin — are excluded
outright; their null is the documented contract of the guard, and flagging 93
of them in one repo is how a gate gets disabled (A8). Everything else needs
the annotation: `catch-empty-ok: <reason>`, reason required.

Exclusions: test files and fixture dirs. Not-applicable is stated, never
silent. Exit 1 on any violation.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import SKIP_DIRS, repo_root  # noqa: E402

# Additive (A21): fixture/test-data dirs are not source under S-03's remit —
# extend the shared skip set rather than hand-copy it.
SKIP = SKIP_DIRS | {"fixtures", "__fixtures__", "testdata"}
EXT = (".py", ".ts", ".tsx", ".js", ".jsx")
TESTY = re.compile(r"(^|[._-])test|spec\.|^tests?$")
IDIOM = re.compile(r"(?:request|response|req|res)\.json\(\)\s*\.catch\(")
PATTERNS = [
    # catch (e) { ...bounded statements...; return [] } — the return-empty must
    # END the block; statements before it are allowed (A16: the flagship live
    # sites called reportSwallowed(...) first and escaped the return-first form).
    re.compile(r"catch\s*(?:\([^)]*\))?\s*\{[^{}]{0,240}?return\s+(?:\[\]|\{\}|null|undefined)\s*;?\s*\}"),
    # .catch(() => [])  /  .catch(e => null)
    re.compile(r"\.catch\(\s*(?:\([^)]*\)|\w+)?\s*=>\s*(?:\[\]|\{\}|null|undefined|\(\s*(?:\[\]|\{\})\s*\))\s*\)"),
    # .catch(() => { return []; })  — block-bodied promise handler
    re.compile(r"\.catch\(\s*(?:\([^)]*\)|\w+)?\s*=>\s*\{[^{}]{0,240}?return\s+(?:\[\]|\{\}|null|undefined)\s*;?\s*\}"),
    # python: except ...: up to 3 bounded statements, then return-empty
    re.compile(r"except[^:\n]*:\s*(?:#[^\n]*)?\n(?:\s+[^\n]{1,120}\n){0,3}?\s*return\s+(?:\[\]|\{\}|None|set\(\)|dict\(\)|list\(\))\s*(?:#|$|\n)"),
]
OK = re.compile(r"catch-empty-ok:\s*(\S.*)?")


def main():
    base = repo_root()
    findings, bare, scanned = [], [], 0
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in SKIP and not d.startswith(".") and not TESTY.search(d)]
        for name in filenames:
            if not name.endswith(EXT) or TESTY.search(name):
                continue
            path = os.path.join(dirpath, name)
            if os.path.abspath(path) == os.path.abspath(__file__):
                continue
            rel = os.path.relpath(path, base)
            scanned += 1
            content = open(path, encoding="utf-8", errors="replace").read()
            lines = content.splitlines()
            for pat in PATTERNS:
                for m in pat.finditer(content):
                    i = content.count("\n", 0, m.start())
                    line = lines[i] if i < len(lines) else ""
                    if IDIOM.search(line):
                        continue  # body-parse guard idiom — excluded by design (A16)
                    ann = OK.search(line) or (OK.search(lines[i - 1]) if i else None)
                    if ann:
                        if not (ann.group(1) or "").strip():
                            bare.append(f"{rel}:{i + 1}")
                        continue
                    findings.append(f"{rel}:{i + 1}  {line.strip()[:100]}")

    if not scanned:
        print("check_catch_empty: NOTE — no source files in scope; S-03 not applicable.")
        return 0
    fail = False
    if findings:
        fail = True
        print(f"S-03 VIOLATIONS — catch returns empty ({len(findings)}):")
        for f in findings:
            print(f"  {f}")
        print("A failure must be distinguishable from an empty result. Rethrow, report,")
        print("or return an explicit error state — or annotate `catch-empty-ok: <reason>`.")
    if bare:
        fail = True
        print(f"S-03: catch-empty-ok annotation WITHOUT a reason ({len(bare)}): " + ", ".join(bare))
    if not fail:
        print(f"check_catch_empty: OK — {scanned} file(s) clean (S-03).")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
