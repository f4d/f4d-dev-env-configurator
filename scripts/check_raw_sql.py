#!/usr/bin/env python3
"""
D-06 — no raw SQL in route handlers.

Scans handler-layer directories (any path segment named routes/, handlers/,
controllers/, api/, endpoints/) for SQL statements embedded in string literals.
SQL belongs behind the data layer; a query string in a handler bypasses every
invariant the data layer holds.

Escape hatch for a genuine exception: annotate the line (or the line above)
`raw-sql-ok: <reason>`. An annotation without a reason is itself a violation —
an unexplained exception teaches nothing and outlives its author.

If the repo has no handler-layer directories the check reports that and passes:
not-applicable is a stated fact, never silence (A8 — a gate that fires wrongly
gets disabled, and a disabled gate protects nothing).
Exit 1 on any violation. Exit 0 clean.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import SKIP_DIRS, repo_root  # noqa: E402

HANDLER_DIRS = {"routes", "handlers", "controllers", "api", "endpoints"}
# Additive (A21): migrations/db/sql genuinely need excluding here — raw SQL
# living there is expected, not a D-06 violation. fixtures/testdata are not
# source either. Extend the shared skip set rather than hand-copy it.
SKIP = SKIP_DIRS | {"migrations", "db", "sql", "fixtures", "__fixtures__", "testdata"}
EXT = (".py", ".ts", ".tsx", ".js", ".jsx")
SQL = re.compile(
    r"""['"`]\s*(?:SELECT\s+[\w*,\s]+\s+FROM\s|INSERT\s+INTO\s|UPDATE\s+\w+\s+SET\s|DELETE\s+FROM\s|DROP\s+(?:TABLE|INDEX)\s|ALTER\s+TABLE\s|TRUNCATE\s+TABLE\s)""",
    re.IGNORECASE,
)
OK = re.compile(r"raw-sql-ok:\s*(\S.*)?")


def main():
    base = repo_root()
    findings, bare_annotations, scanned = [], [], 0
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in SKIP and not d.startswith(".")]
        if not (set(dirpath.split(os.sep)) & HANDLER_DIRS):
            continue
        for name in filenames:
            if not name.endswith(EXT):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, base)
            scanned += 1
            content = open(path, encoding="utf-8", errors="replace").read()
            lines = content.splitlines()
            # Whole-content scan: a multiline template literal puts the opening
            # quote and the SQL verb on different lines, which a per-line scan
            # walks straight past — the exact handlers D-06 exists to protect.
            for m in SQL.finditer(content):
                i = content.count("\n", 0, m.start())  # 0-based line of the match
                line = lines[i] if i < len(lines) else ""
                ann = OK.search(line) or (OK.search(lines[i - 1]) if i else None)
                if ann:
                    if not (ann.group(1) or "").strip():
                        bare_annotations.append(f"{rel}:{i + 1}")
                    continue
                findings.append(f"{rel}:{i + 1}  {line.strip()[:100]}")

    if not scanned:
        print("check_raw_sql: NOTE — no handler-layer directories (routes/, handlers/, "
              "controllers/, api/, endpoints/) found; D-06 not applicable to this repo shape.")
        return 0

    fail = False
    if findings:
        fail = True
        print(f"D-06 VIOLATIONS — raw SQL in handlers ({len(findings)}):")
        for f in findings:
            print(f"  {f}")
        print("Move the query behind the data layer, or annotate `raw-sql-ok: <reason>` for a genuine exception.")
    if bare_annotations:
        fail = True
        print(f"D-06: raw-sql-ok annotation WITHOUT a reason ({len(bare_annotations)}): " + ", ".join(bare_annotations))
    if not fail:
        print(f"check_raw_sql: OK — {scanned} handler file(s) clean (D-06).")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
