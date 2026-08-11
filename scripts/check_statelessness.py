#!/usr/bin/env python3
"""
ST-01..ST-06 — statefulness scan.

Finds state that will work on one instance and break on two. This failure class
presents as intermittent flakiness rather than as a defect, so a static scan
catches more of it than review does.

Deliberately conservative — reports with a rule ID and a reason, never guesses.
Exit 1 on any finding. Set STATELESS_SINGLE_INSTANCE=1 to downgrade to warnings
for a project that genuinely runs one instance forever.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import SKIP_DIRS, repo_root  # noqa: E402

EXT = (".py", ".ts", ".tsx", ".js", ".jsx")

PATTERNS = [
    # (rule, regex, why)
    ("ST-01", r"^\s*(?:const|let|var)\s+\w*(?:cache|Cache|store|Store|registry|sessions?)\s*(?::[^=]+)?=\s*(?:new\s+Map\(|\{\}|\[\])",
     "module-level mutable collection — per-instance state pretending to be a cache. "
     "If it is populated ONLY at import time (a registration registry), that is safe: "
     "annotate `stateless-ok import-time registration` — see statelessness.md § Import-time registries"),
    ("ST-01", r"^\s*_?\w*(?:cache|CACHE|_store|SESSIONS|_registry)\s*(?::\s*[Dd]ict[^=]*)?=\s*(?:\{\}|\[\]|dict\(\)|set\(\))",
     "module-level mutable collection — per-instance state"),
    ("ST-02", r"\b(?:threading\.Lock|asyncio\.Lock|new\s+Mutex|Semaphore)\s*\(",
     "in-process lock — two instances both enter the critical section"),
    ("ST-03", r"\b(?:setInterval|setTimeout)\s*\(.*\b(?:60000|3600000|86400000)\b|\bschedule\.every|\bBackgroundScheduler|\bnode-cron|\bcron\.schedule",
     "in-process scheduler — N instances fire the job N times"),
    ("ST-04", r"\b(?:tempfile\.(?:mkdtemp|NamedTemporaryFile)|os\.makedirs\(\s*['\"]\.?/?(?:tmp|uploads|files)|fs\.writeFileSync\(\s*['\"]\.?/?(?:tmp|uploads))",
     "local disk write — ephemeral, and invisible to other instances"),
    ("ST-05", r"\b(?:run_migrations|migrate\(\)|alembic\.command\.upgrade|prisma migrate deploy)\b",
     "possible migration at boot — instances race on deploy"),
    ("ST-06", r"\b(?:express-session|MemoryStore|session\(\{[^}]*store\s*:\s*undefined)",
     "in-memory session store — user is logged out when routed to another instance"),
    ("ST-07", r"\b(?:rate_?limit|RateLimit|limiter)\w*\s*=\s*(?:\{\}|new\s+Map\(|defaultdict)",
     "in-process rate limiter — N instances allow N times the limit"),
]

ALLOW = re.compile(r"#\s*stateless-ok|//\s*stateless-ok")


def main():
    base = repo_root()
    single = os.environ.get("STATELESS_SINGLE_INSTANCE") == "1"
    findings = []

    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
        if any(p in dirpath for p in ("test", "spec", "__tests__", "migrations")):
            continue
        for fn in filenames:
            if not fn.endswith(EXT):
                continue
            path = os.path.join(dirpath, fn)
            # A scanner must not match its own pattern table.
            if os.path.abspath(path) == os.path.abspath(__file__):
                continue
            try:
                lines = open(path, errors="ignore").read().splitlines()
            except Exception:
                continue
            for i, line in enumerate(lines, 1):
                if ALLOW.search(line):
                    continue
                for rule, pat, why in PATTERNS:
                    if re.search(pat, line, re.M):
                        findings.append((rule, os.path.relpath(path, base), i, line.strip()[:80], why))
                        break

    if not findings:
        print("Statelessness scan clean.")
        return 0

    print("STATEFULNESS FINDINGS\n")
    print("These work on one instance and fail intermittently on two.\n")
    for rule, path, line, src, why in findings:
        print(f"  [{rule}] {path}:{line}")
        print(f"          {src}")
        print(f"          {why}\n")

    print(f"{len(findings)} finding(s). See statelessness.md and REGISTRY.md ST-*.")
    print("If a case is genuinely safe, annotate the line `stateless-ok` with a reason.")

    if single:
        print("\nSTATELESS_SINGLE_INSTANCE=1 — reported as warnings, not failing.")
        print("Remove that flag the day this project scales past one instance.")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
