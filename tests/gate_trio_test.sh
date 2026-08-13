#!/usr/bin/env bash
# Red-then-green harness for the C-06 / D-06 / S-07 gate trio.
# Every guard is seen to fail before it counts (G-01); every cannot-evaluate
# path blocks (G-03); every not-applicable path states itself (A8).
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() { if [ "$2" -eq "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (expected exit $2, got $3)"; fi }

# ---------- C-06 check_commits ----------
T1="$(mktemp -d)"
( cd "$T1" && git init -q && git config user.email t@t && git config user.name t \
  && git commit -q --allow-empty -m "chore: baseline" && git branch -M main && git checkout -q -b feat )
( cd "$T1" && git commit -q --allow-empty -m "feat(scope): a conventional subject" \
  && BASE_REF=main python3 "$KIT/scripts/check_commits.py" >/dev/null 2>&1 ); check "C-06 green: conventional passes" 0 $?
( cd "$T1" && git commit -q --allow-empty -m "added some stuff" \
  && BASE_REF=main python3 "$KIT/scripts/check_commits.py" >/dev/null 2>&1 ); check "C-06 red: unconventional blocks" 1 $?
( cd "$T1" && git reset -q --hard HEAD~1 && git commit -q --allow-empty -m "feat: $(printf 'x%.0s' {1..120})" \
  && BASE_REF=main python3 "$KIT/scripts/check_commits.py" >/dev/null 2>&1 ); check "C-06 red: >100 chars blocks" 1 $?
( cd "$T1" && git reset -q --hard HEAD~1 && git commit -q --allow-empty -m 'Revert "feat: something"' \
  && BASE_REF=main python3 "$KIT/scripts/check_commits.py" >/dev/null 2>&1 ); check "C-06 green: Revert skipped" 0 $?
( cd "$T1" && git checkout -q main \
  && BASE_REF=main python3 "$KIT/scripts/check_commits.py" >/dev/null 2>&1 ); check "C-06 red: empty range blocks (fail-loud)" 1 $?
( cd "$T1" && python3 "$KIT/scripts/check_commits.py" >/dev/null 2>&1 ); check "C-06 red: unset BASE_REF blocks (fail-loud)" 1 $?
rm -rf "$T1"

# ---------- D-06 check_raw_sql ----------
T2="$(mktemp -d)"
( cd "$T2" && git init -q ) && mkdir -p "$T2/src/routes" "$T2/src/db"
echo 'const q = db.select().from(users);' > "$T2/src/routes/clean.ts"
( cd "$T2" && python3 "$KIT/scripts/check_raw_sql.py" >/dev/null 2>&1 ); check "D-06 green: clean handler passes" 0 $?
echo 'const q = `SELECT id, name FROM users WHERE id = ${id}`;' > "$T2/src/routes/dirty.ts"
( cd "$T2" && python3 "$KIT/scripts/check_raw_sql.py" >/dev/null 2>&1 ); check "D-06 red: raw SQL in handler blocks" 1 $?
printf '// raw-sql-ok: read-only report query, reviewed 2026-08-11\nconst q = `SELECT id, name FROM users WHERE id = 1`;\n' > "$T2/src/routes/dirty.ts"
( cd "$T2" && python3 "$KIT/scripts/check_raw_sql.py" >/dev/null 2>&1 ); check "D-06 green: annotated-with-reason passes" 0 $?
printf '// raw-sql-ok:\nconst q = `SELECT id, name FROM users WHERE id = 1`;\n' > "$T2/src/routes/dirty.ts"
( cd "$T2" && python3 "$KIT/scripts/check_raw_sql.py" >/dev/null 2>&1 ); check "D-06 red: bare annotation blocks" 1 $?
echo 'const m = `SELECT x FROM y`;' > "$T2/src/db/migration.ts"
rm "$T2/src/routes/dirty.ts"
( cd "$T2" && python3 "$KIT/scripts/check_raw_sql.py" >/dev/null 2>&1 ); check "D-06 green: db/ layer excluded" 0 $?
printf 'const q = `\n  SELECT id, name\n  FROM users\n  WHERE id = 1`;\n' > "$T2/src/routes/multiline.ts"
( cd "$T2" && python3 "$KIT/scripts/check_raw_sql.py" >/dev/null 2>&1 ); check "D-06 red: MULTILINE template literal blocks" 1 $?
rm "$T2/src/routes/multiline.ts"
T2b="$(mktemp -d)"; ( cd "$T2b" && git init -q && mkdir lib && python3 "$KIT/scripts/check_raw_sql.py" 2>&1 | grep -q "NOTE" ); check "D-06 states not-applicable (A8)" 0 $?
rm -rf "$T2" "$T2b"

# ---------- S-07 check_pure_imports ----------
T3="$(mktemp -d)"
( cd "$T3" && git init -q ) && mkdir -p "$T3/src/pure" "$T3/src/loaders"
echo 'export const sum = (a: number, b: number) => a + b;' > "$T3/src/pure/math.ts"
echo 'import axios from "axios";' > "$T3/src/loaders/fetcher.ts"
( cd "$T3" && python3 "$KIT/scripts/check_pure_imports.py" >/dev/null 2>&1 ); check "S-07 green: pure math passes; loaders/ untouched" 0 $?
echo 'import axios from "axios";' > "$T3/src/pure/leak.ts"
( cd "$T3" && python3 "$KIT/scripts/check_pure_imports.py" >/dev/null 2>&1 ); check "S-07 red: axios import in pure/ blocks" 1 $?
echo 'const r = await fetch("https://x");' > "$T3/src/pure/leak.ts"
( cd "$T3" && python3 "$KIT/scripts/check_pure_imports.py" >/dev/null 2>&1 ); check "S-07 red: bare fetch() in pure/ blocks" 1 $?
echo 'import requests' > "$T3/src/pure/leak.py"; rm "$T3/src/pure/leak.ts"
( cd "$T3" && python3 "$KIT/scripts/check_pure_imports.py" >/dev/null 2>&1 ); check "S-07 red: python requests import blocks" 1 $?
printf '# pure-io-ok: boundary shim being extracted, tracked in BACKLOG\nimport requests\n' > "$T3/src/pure/leak.py"
( cd "$T3" && python3 "$KIT/scripts/check_pure_imports.py" >/dev/null 2>&1 ); check "S-07 green: annotated-with-reason passes" 0 $?
echo 'const prefetchAll = (xs) => xs.map(prefetch);' > "$T3/src/pure/nofalse.ts"; rm "$T3/src/pure/leak.py"
( cd "$T3" && python3 "$KIT/scripts/check_pure_imports.py" >/dev/null 2>&1 ); check "S-07 green: 'prefetch(' not a false positive" 0 $?
echo 'from pathlib import Path' > "$T3/src/pure/fsleak.py"
( cd "$T3" && python3 "$KIT/scripts/check_pure_imports.py" >/dev/null 2>&1 ); check "S-07 red: python pathlib import blocks" 1 $?
echo 'data = open("x.json").read()' > "$T3/src/pure/fsleak.py"
( cd "$T3" && python3 "$KIT/scripts/check_pure_imports.py" >/dev/null 2>&1 ); check "S-07 red: bare open() call blocks" 1 $?
echo 'x = reopen(state)' > "$T3/src/pure/fsleak.py"
( cd "$T3" && python3 "$KIT/scripts/check_pure_imports.py" >/dev/null 2>&1 ); check "S-07 green: 'reopen(' not a false positive" 0 $?
rm "$T3/src/pure/fsleak.py"
T3b="$(mktemp -d)"; ( cd "$T3b" && git init -q && mkdir lib && python3 "$KIT/scripts/check_pure_imports.py" 2>&1 | grep -q "NOTE" ); check "S-07 states not-applicable (A8)" 0 $?
rm -rf "$T3" "$T3b"

# ---------- S-03 check_catch_empty ----------
T4="$(mktemp -d)"; ( cd "$T4" && git init -q ) && mkdir -p "$T4/src"
echo 'const x = await load().catch(() => []);' > "$T4/src/a.ts"
( cd "$T4" && python3 "$KIT/scripts/check_catch_empty.py" >/dev/null 2>&1 ); check "S-03 red: arrow catch-empty blocks" 1 $?
printf 'try { x() } catch (e) {\n  return [];\n}\n' > "$T4/src/a.ts"
( cd "$T4" && python3 "$KIT/scripts/check_catch_empty.py" >/dev/null 2>&1 ); check "S-03 red: brace catch-empty blocks" 1 $?
printf 'try:\n    x()\nexcept ValueError:\n    return []\n' > "$T4/src/a.py"; rm "$T4/src/a.ts"
( cd "$T4" && python3 "$KIT/scripts/check_catch_empty.py" >/dev/null 2>&1 ); check "S-03 red: python except-return-empty blocks" 1 $?
printf 'try:\n    x()\nexcept ValueError:  # catch-empty-ok: body-parse guard, null handled at the call site\n    return []\n' > "$T4/src/a.py"
( cd "$T4" && python3 "$KIT/scripts/check_catch_empty.py" >/dev/null 2>&1 ); check "S-03 green: annotated-with-reason passes" 0 $?
printf 'try { x() } catch (e) {\n  reportSwallowed("ctx", e);\n  return [];\n}\n' > "$T4/src/b.ts"; rm "$T4/src/a.py"
( cd "$T4" && python3 "$KIT/scripts/check_catch_empty.py" >/dev/null 2>&1 ); check "S-03 red (A16): multi-statement catch ending in return-empty blocks" 1 $?
echo 'const payload = await request.json().catch(() => null);' > "$T4/src/b.ts"
( cd "$T4" && python3 "$KIT/scripts/check_catch_empty.py" >/dev/null 2>&1 ); check "S-03 green (A16): request-body parse idiom excluded" 0 $?
printf 'const x = await load().catch(() => {\n  return [];\n});\n' > "$T4/src/b.ts"
( cd "$T4" && python3 "$KIT/scripts/check_catch_empty.py" >/dev/null 2>&1 ); check "S-03 red: BLOCK-BODIED promise catch blocks" 1 $?
rm -rf "$T4"

# ---------- O-05 check_log_hygiene ----------
T5="$(mktemp -d)"; ( cd "$T5" && git init -q ) && mkdir -p "$T5/src"
echo 'console.log("incoming", req.body);' > "$T5/src/h.ts"
( cd "$T5" && python3 "$KIT/scripts/check_log_hygiene.py" >/dev/null 2>&1 ); check "O-05 red: logging req.body blocks" 1 $?
printf 'console.log(\n  "incoming",\n  req.body\n);\n' > "$T5/src/h.ts"
( cd "$T5" && python3 "$KIT/scripts/check_log_hygiene.py" >/dev/null 2>&1 ); check "O-05 red: MULTILINE log call blocks" 1 $?
printf '// log-ok: logs the redacted summary only\nconsole.log("incoming", req.body.summary);\n' > "$T5/src/h.ts"
( cd "$T5" && python3 "$KIT/scripts/check_log_hygiene.py" >/dev/null 2>&1 ); check "O-05 green: annotated-with-reason passes" 0 $?
echo 'console.log("processed", count);' > "$T5/src/h.ts"
( cd "$T5" && python3 "$KIT/scripts/check_log_hygiene.py" >/dev/null 2>&1 ); check "O-05 green: clean log passes" 0 $?
rm -rf "$T5"

# ---------- C-08 check_test_count ----------
T6="$(mktemp -d)"
( cd "$T6" && git init -q && git config user.email t@t && git config user.name t \
  && mkdir tests && printf 'async def test_a():\n    pass\ndef test_b():\n    pass\n' > tests/test_x.py \
  && git add -A && git commit -qm "chore: two tests" && git branch -M main && git checkout -q -b feat \
  && printf 'def test_a():\n    pass\n' > tests/test_x.py )
( cd "$T6" && BASE_REF=main python3 "$KIT/scripts/check_test_count.py" >/dev/null 2>&1 ); check "C-08 red: test deletion blocks" 1 $?
( cd "$T6" && BASE_REF=main PR_BODY="test-removal-ok: test_b covered dead feature Z, replaced by integration suite" python3 "$KIT/scripts/check_test_count.py" >/dev/null 2>&1 ); check "C-08 green: stated waiver passes" 0 $?
( cd "$T6" && python3 "$KIT/scripts/check_test_count.py" 2>/dev/null | grep -q "NOTE" ); check "C-08 states not-evaluable without BASE_REF" 0 $?
rm -rf "$T6"

# ---------- C-08 baseline/worktree skip-dir agreement (PR #33 review finding) ----------
# count_worktree() prunes SKIP_DIRS/dot-dirs (A21); count_at(ref) read every
# tracked path from `git ls-tree` unfiltered. A tracked test file sitting
# under a dot-directory at BASE_REF (e.g. .ci/test_hidden.py) was therefore
# counted in the baseline but never in the worktree, so a completely
# unchanged PR reported a false test-count regression (repro'd: tests 1 -> 0).
T6b="$(mktemp -d)"
( cd "$T6b" && git init -q && git config user.email t@t && git config user.name t \
  && mkdir -p tests .ci \
  && printf 'def test_real():\n    pass\n' > tests/test_real.py \
  && printf 'def test_hidden():\n    pass\n' > .ci/test_hidden.py \
  && git add -A && git commit -qm "chore: one real test, one dot-dir test" && git branch -M main )
( cd "$T6b" && BASE_REF=main python3 "$KIT/scripts/check_test_count.py" >/dev/null 2>&1 ); check "C-08 green (repro): unchanged PR does not regress over a skip-dir baseline test" 0 $?
( cd "$T6b" && rm tests/test_real.py && BASE_REF=main python3 "$KIT/scripts/check_test_count.py" >/dev/null 2>&1 ); check "C-08 red: real test deletion still blocks despite a skip-dir baseline test" 1 $?
rm -rf "$T6b"

# ---------- G-05 fixture case-diff (in check_fixtures) ----------
T7="$(mktemp -d)"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
( cd "$T7" && git init -q && git config user.email t@t && git config user.name t && mkdir -p vendorx/fixtures
  for n in happy empty rate_limited malformed; do
    printf '{"_meta":{"recorded_at":"%s","source":"t"},"case1":1,"case2":2,"case3":3}' "$NOW" > "vendorx/fixtures/$n.json"
  done
  git add -A && git commit -qm "chore: fixtures" && git branch -M main && git checkout -q -b feat
  printf '{"_meta":{"recorded_at":"%s","source":"t"},"case1":1}' "$NOW" > "vendorx/fixtures/happy.json" )
( cd "$T7" && BASE_REF=main python3 "$KIT/scripts/check_fixtures.py" >/dev/null 2>&1 ); check "G-05 red: fixture case deletion blocks" 1 $?
( cd "$T7" && BASE_REF=main PR_BODY="fixture-case-removed-ok: case2/3 duplicated case1 after vendor collapsed the field" python3 "$KIT/scripts/check_fixtures.py" >/dev/null 2>&1 ); check "G-05 green: stated waiver passes" 0 $?
rm -rf "$T7"

# ---------- G-05 baseline skip-dir agreement (PR #33 review finding) ----------
# find_fixture_dirs() prunes SKIP_DIRS/dot-dirs (A21); g05_case_diff()'s own
# baseline enumeration (`git ls-tree` against BASE_REF) did not, so a fixture
# tracked under a dot-directory (e.g. .cache/vendor/fixtures/happy.json) that
# find_fixture_dirs() now declares out of scope still failed G-05 when
# deleted, because the baseline list never excluded it in the first place.
T7b="$(mktemp -d)"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
( cd "$T7b" && git init -q && git config user.email t@t && git config user.name t
  mkdir -p vendorx/fixtures .cache/vendor/fixtures
  for n in happy empty rate_limited malformed; do
    printf '{"_meta":{"recorded_at":"%s","source":"t"},"case1":1,"case2":2}' "$NOW" > "vendorx/fixtures/$n.json"
  done
  printf '{"_meta":{"recorded_at":"%s","source":"t"},"case1":1,"case2":2}' "$NOW" > ".cache/vendor/fixtures/happy.json"
  git add -A && git commit -qm "chore: visible fixtures plus a dot-dir fixture" && git branch -M main
  rm -rf .cache )
( cd "$T7b" && BASE_REF=main python3 "$KIT/scripts/check_fixtures.py" >/dev/null 2>&1 ); check "G-05 green (repro): deleting an out-of-scope dot-dir fixture is not a case-removal" 0 $?
( cd "$T7b" && rm vendorx/fixtures/empty.json && BASE_REF=main python3 "$KIT/scripts/check_fixtures.py" >/dev/null 2>&1 ); check "G-05 red: real (non-skip-dir) fixture deletion still blocks" 1 $?
rm -rf "$T7b"

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
