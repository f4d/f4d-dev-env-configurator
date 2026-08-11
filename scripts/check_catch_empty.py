#!/usr/bin/env python3
"""
S-03 — the `catch → []` trap.

A catch that returns an empty collection (or null) makes a failure
indistinguishable from an empty result: every downstream "is anything
missing?" gate passes vacuously, and the outage ships as plausible data.
Proven live: a failed pipeline fetch published raw IDs as report rows, a
failed tag fetch drove duplicate tag creation (GHL-MCP audit F3–F5).

Escape hatch: annotate the catch line (or the line above)
`catch-empty-ok: <reason>` — a reason is required; the legitimate cases
(body-parse guards whose null is explicitly handled) deserve one sentence.

Exclusions: test files and fixture dirs. Not-applicable is stated, never
silent. Exit 1 on any violation.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import repo_root  # noqa: E402

SKIP = (".git", "node_modules", ".venv", "dist", "build", ".next", "fixtures", "__fixtures__", "testdata")
EXT = (".py", ".ts", ".tsx", ".js", ".jsx")
TESTY = re.compile(r"(^|[._-])test|spec\.|^tests?$")
PATTERNS = [
    # catch (e) { return [] }  /  catch { return null }  — brace body, first statement
    re.compile(r"catch\s*(?:\([^)]*\))?\s*\{\s*(?://[^\n]*\n\s*)?return\s+(?:\[\]|\{\}|null|undefined)\s*[;}\n]"),
    # .catch(() => [])  /  .catch(e => null)
    re.compile(r"\.catch\(\s*(?:\([^)]*\)|\w+)?\s*=>\s*(?:\[\]|\{\}|null|undefined|\(\s*(?:\[\]|\{\})\s*\))\s*\)"),
    # python: except ...: return [] / {} / None / set() / dict() / list()
    re.compile(r"except[^:\n]*:\s*(?:#[^\n]*)?\n\s*return\s+(?:\[\]|\{\}|None|set\(\)|dict\(\)|list\(\))\s*(?:#|$|\n)"),
]
OK = re.compile(r"catch-empty-ok:\s*(\S.*)?")


def main():
    base = repo_root()
    findings, bare, scanned = [], [], 0
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in SKIP and not TESTY.search(d)]
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
