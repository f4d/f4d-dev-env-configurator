#!/usr/bin/env python3
"""
S-07 — a pure function must not fetch.

Scans every directory named pure/ for IO: network/DB/filesystem imports, and
bare fetch() calls (the global needs no import). Pure modules take settled
values; the layer that CAN do IO resolves them and passes them in.

Escape hatch: annotate the line (or the line above) `pure-io-ok: <reason>`.
An annotation without a reason is itself a violation.

If the repo has no pure/ directories the check reports that and passes:
not-applicable is a stated fact, never silence (A8).
Exit 1 on any violation. Exit 0 clean.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import SKIP_DIRS, repo_root  # noqa: E402

# Additive (A21): fixture/test-data dirs are not source under S-07's remit —
# extend the shared skip set rather than hand-copy it.
SKIP = SKIP_DIRS | {"fixtures", "__fixtures__", "testdata"}
EXT = (".py", ".ts", ".tsx", ".js", ".jsx")
IO_MODULES = (
    "requests", "httpx", "aiohttp", "urllib.request", "socket", "smtplib", "ftplib",
    "psycopg", "psycopg2", "sqlalchemy", "boto3", "redis", "pymongo",
    "axios", "node-fetch", "undici", "node:http", "node:https", "node:net", "node:fs",
    "ioredis", "mongodb", "@aws-sdk",
)
IMPORT = re.compile(
    r"""^\s*(?:import\s+.*?from\s+['"]({mods})(?:['"/])|import\s+['"]?({mods})['"]?(?:\s|$|;)|from\s+({mods})\s+import|(?:const|let|var)\s+.*=\s*require\(\s*['"]({mods})['"]\s*\))""".format(
        mods="|".join(re.escape(m) for m in IO_MODULES)
    )
)
# 'pg', 'mysql2', 'fs', 'http', 'https' matched exactly to avoid false hits on longer names.
EXACT_MODULES = re.compile(r"""(?:from\s+['"]|import\s+['"]|require\(\s*['"])(pg|mysql2?|fs|http|https|net)['"]""")
# Python filesystem/IO entry points: statement-level imports plus the bare
# builtin open() call — file IO needs no import at all in Python.
PY_IO_IMPORT = re.compile(r"^\s*(?:import|from)\s+(os|pathlib|shutil|tempfile|io|glob)\b")
OPEN_CALL = re.compile(r"""(?<![.\w])open\s*\(""")
FETCH_CALL = re.compile(r"""(?<![.\w])fetch\s*\(""")
OK = re.compile(r"pure-io-ok:\s*(\S.*)?")


def main():
    base = repo_root()
    findings, bare_annotations, scanned = [], [], 0
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in SKIP and not d.startswith(".")]
        if "pure" not in dirpath.split(os.sep):
            continue
        for name in filenames:
            if not name.endswith(EXT):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, base)
            scanned += 1
            lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
            is_py = name.endswith(".py")
            for i, line in enumerate(lines):
                hit = (IMPORT.search(line) or EXACT_MODULES.search(line) or FETCH_CALL.search(line)
                       or (is_py and (PY_IO_IMPORT.search(line) or OPEN_CALL.search(line))))
                if not hit:
                    continue
                ann = OK.search(line) or (OK.search(lines[i - 1]) if i else None)
                if ann:
                    if not (ann.group(1) or "").strip():
                        bare_annotations.append(f"{rel}:{i + 1}")
                    continue
                findings.append(f"{rel}:{i + 1}  {line.strip()[:100]}")

    if not scanned:
        print("check_pure_imports: NOTE — no pure/ directories found; S-07 not applicable to this repo shape.")
        return 0

    fail = False
    if findings:
        fail = True
        print(f"S-07 VIOLATIONS — IO reachable from pure/ ({len(findings)}):")
        for f in findings:
            print(f"  {f}")
        print("Resolve the value in the layer that can do IO and pass it in — or annotate `pure-io-ok: <reason>`.")
    if bare_annotations:
        fail = True
        print(f"S-07: pure-io-ok annotation WITHOUT a reason ({len(bare_annotations)}): " + ", ".join(bare_annotations))
    if not fail:
        print(f"check_pure_imports: OK — {scanned} pure file(s) clean (S-07).")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
