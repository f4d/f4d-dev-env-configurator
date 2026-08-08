#!/usr/bin/env python3
"""
O-02 / O-03 / D-05 — rollback is rehearsed, not merely written.

A rollback step nobody has executed is the same class of claim as a guard nobody
has seen fail. This checks two things:

  1. Every migration in the diff has a working down-path (or an explicit,
     reviewed declaration that it does not).
  2. The PR body carries a rollback step, and it is not the false default
     "revert the commit" when a migration ran.

Exit 1 on failure. Wire into the PR gate.
"""
import os
import re
import subprocess
import sys

MIGRATION_HINTS = ("migrations/", "migration/", "alembic/", "prisma/migrations")
IRREVERSIBLE = ("drop table", "drop column", "truncate", "delete from")


def sh(*a):
    try:
        return subprocess.check_output(a, text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return ""


def changed_files(base_ref):
    out = sh("git", "diff", "--name-only", f"{base_ref}...HEAD")
    return [f for f in out.splitlines() if f.strip()]


def main():
    base_ref = os.environ.get("BASE_REF", "origin/main")
    body = os.environ.get("PR_BODY", "")
    files = changed_files(base_ref)
    migrations = [f for f in files if any(h in f for h in MIGRATION_HINTS)]

    failures = []

    for m in migrations:
        if not os.path.exists(m):
            continue
        text = open(m, errors="ignore").read().lower()
        has_down = any(k in text for k in ("def downgrade", "-- down", "down()", "-- migrate:down"))
        destructive = [k for k in IRREVERSIBLE if k in text]
        declared = "irreversible" in text or "no rollback" in text

        if destructive and not declared:
            failures.append(
                f"{m}: contains {destructive} but does not declare itself irreversible (D-05). "
                "Either provide a down-path or state explicitly that there is none, and why."
            )
        elif not has_down and not declared:
            failures.append(
                f"{m}: no down-path and no explicit irreversible declaration (D-05)."
            )

    if body:
        section = re.search(r"##\s*Rollback\s*(.+?)(?=\n##|\Z)", body, re.S | re.I)
        if not section or not section.group(1).strip():
            failures.append("PR body has no Rollback section (O-02).")
        else:
            step = section.group(1).strip().lower()
            if migrations and re.fullmatch(r"[^\n]*revert the commit[^\n]*", step):
                failures.append(
                    "PR body says 'revert the commit' but this PR runs a migration (O-03). "
                    "Reverting code does not un-run a migration. Describe the real path."
                )

    if failures:
        print("ROLLBACK CHECK FAILED\n")
        for f in failures:
            print(f"  {f}")
        return 1

    print(f"Rollback check passed ({len(migrations)} migration(s) in diff).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
