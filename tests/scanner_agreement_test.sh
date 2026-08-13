#!/usr/bin/env bash
# A21 — every scanner must agree that a dot-prefixed directory does not exist.
#
# Regression guard for the 13->345 style bug: check_test_count.py (and five
# other scanners) walked into a dot-prefixed directory that
# check_statelessness.py / check_guess_lists.py already knew to skip, so the
# same repo produced different findings and a wildly different test count
# depending on which gate looked at it. One shared fixture tree, one trigger
# per scanner, all planted inside a single dot-directory — every scanner must
# report clean / correct, proving the dot-directory is uniformly invisible.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() { if [ "$2" -eq "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (expected $2, got $3)"; fi }

T="$(mktemp -d)"
( cd "$T" && git init -q )

# A visible, clean source file — proves a "clean" verdict below means the
# scanner actually walked the repo, not that it saw nothing at all.
mkdir -p "$T/src"
echo 'export const sum = (a, b) => a + b;' > "$T/src/clean.ts"

# The dot-prefixed directory. Nothing under here may ever surface in a
# finding or a count — that is the entire fixture.
mkdir -p "$T/.cache/api" "$T/.cache/pure" "$T/.cache/vendorx/fixtures"
echo 'const registry: Record<string, C> = {};' > "$T/.cache/registry.ts"                       # ST-01
echo 'const q = `SELECT id, name FROM users WHERE id = 1`;' > "$T/.cache/api/handler.ts"        # D-06
echo 'import axios from "axios";' > "$T/.cache/pure/leak.ts"                                    # S-07
echo 'console.log("incoming", req.body);' > "$T/.cache/logger.ts"                               # O-05
echo 'const x = await load().catch(() => []);' > "$T/.cache/swallow.ts"                         # S-03
echo 'const ROLES = ["admin", "editor", "viewer"];' > "$T/.cache/twin_a.ts"                     # S-05
echo 'const PERMS = ["admin", "editor", "viewer"];' > "$T/.cache/twin_b.ts"                     # S-05 (dupe of twin_a)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"_meta":{"recorded_at":"%s","source":"t"},"case1":1}' "$NOW" > "$T/.cache/vendorx/fixtures/happy.json"  # I-02, incomplete on purpose
for n in 1 2 3 4 5; do
  printf 'it("phantom %s a", () => {});\nit("phantom %s b", () => {});\n' "$n" "$n" > "$T/.cache/phantom_$n.test.js"  # C-08
done

# A small, KNOWN-good set of real test cases — the only ones any count below
# is allowed to include.
mkdir -p "$T/tests"
printf 'def test_real_a():\n    pass\ndef test_real_b():\n    pass\n' > "$T/tests/test_real.py"

( cd "$T" && python3 "$KIT/scripts/check_statelessness.py" >/dev/null 2>&1 ); check "ST-01 (statelessness): dot-dir registry invisible" 0 $?
( cd "$T" && python3 "$KIT/scripts/check_raw_sql.py" >/dev/null 2>&1 );       check "D-06 (raw-sql): dot-dir handler invisible" 0 $?
( cd "$T" && python3 "$KIT/scripts/check_pure_imports.py" >/dev/null 2>&1 ); check "S-07 (pure-imports): dot-dir pure/ invisible" 0 $?
( cd "$T" && python3 "$KIT/scripts/check_log_hygiene.py" >/dev/null 2>&1 );  check "O-05 (log-hygiene): dot-dir log call invisible" 0 $?
( cd "$T" && python3 "$KIT/scripts/check_catch_empty.py" >/dev/null 2>&1 ); check "S-03 (catch-empty): dot-dir catch-empty invisible" 0 $?
( cd "$T" && python3 "$KIT/scripts/check_guess_lists.py" >/dev/null 2>&1 ); check "S-05 (guess-lists): dot-dir duplicate list invisible" 0 $?
( cd "$T" && python3 "$KIT/scripts/check_fixtures.py" >/dev/null 2>&1 );    check "I-02 (fixtures): dot-dir fixture dir invisible" 0 $?

COUNT=$(cd "$T" && python3 -c "
import sys
sys.path.insert(0, '$KIT/scripts')
import check_test_count as c
print(c.count_worktree())
")
check "C-08 (test-count): dot-dir test cases excluded, count stays 2" 2 "$COUNT"

rm -rf "$T"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
