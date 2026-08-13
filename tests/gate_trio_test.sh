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

# ---------- S-05 check_guess_lists — object-member lists (A17) ----------
# check_guess_lists previously matched only flat string-literal collections;
# GHL-MCP's real CUSTOM_OBJECTS is six files each redeclaring an array of
# OBJECTS that share repeated objectKey values, which passed clean. Red-green
# was measured against a fixture mirroring that real shape (label/objectKey,
# and a label/objectId/objectKey variant) before this section existed: the
# pre-fix gate reported "No duplicate constant lists found" on it; the
# fingerprinting below is what makes the same fixture block.
T8="$(mktemp -d)"; ( cd "$T8" && git init -q ) && mkdir -p "$T8/src"
printf "const CUSTOM_OBJECTS = [\n  { label: 'Communities', objectKey: 'custom_objects.communities' },\n  { label: 'Site Maps', objectKey: 'custom_objects.site_maps' },\n  { label: 'Community Residents', objectKey: 'custom_objects.community_residents' },\n  { label: 'Buildings - Roof Records', objectKey: 'custom_objects.buildings_roof_records' }\n];\n" > "$T8/src/mcpServer.ts"
printf "const REPORTING_CUSTOM_OBJECTS = [\n  { label: 'Communities', objectId: '69c2f45a3d29b2d7bf19d0cf', objectKey: 'custom_objects.communities' },\n  { label: 'Site Maps', objectId: '69c300517019dc455d881a00', objectKey: 'custom_objects.site_maps' },\n  { label: 'Community Residents', objectId: '69c2f3769aa1012c02b2b87b', objectKey: 'custom_objects.community_residents' },\n  { label: 'Building - Roof Records', objectId: '69f371e87a6703dfdfe98fef', objectKey: 'custom_objects.buildings_roof_records' }\n];\n" > "$T8/src/mainReportFixed.ts"
( cd "$T8" && python3 "$KIT/scripts/check_guess_lists.py" >/dev/null 2>&1 ); check "S-05 red: object-array objectKey repeated across 2 files blocks (GHL-MCP CUSTOM_OBJECTS shape)" 1 $?
# Captured to a variable rather than piped directly into grep: with
# `pipefail` (set at the top of this file), python3's own exit 1 — correct,
# it found a duplicate — would otherwise clobber grep's exit code and make
# this assertion meaningless regardless of what grep found.
OUT8="$(cd "$T8" && python3 "$KIT/scripts/check_guess_lists.py" 2>&1)"
printf '%s' "$OUT8" | grep -q "objectKey: custom_objects"; check "S-05: finding names the objectKey fingerprint, not just a bare value list" 0 $?
rm "$T8/src/mainReportFixed.ts"
( cd "$T8" && python3 "$KIT/scripts/check_guess_lists.py" >/dev/null 2>&1 ); check "S-05 green: same object-array shape in only 1 file does not block" 0 $?
rm -rf "$T8"

# A lone repeated column that never varies (every entry has the same type/
# active pair) has no per-array-unique property to fingerprint on at all —
# must not crash and must not false-flag (G-03 fail-loud contract: "cannot
# find a stable key" is reported as nothing found, never as a false pass
# dressed up as a real check, and never as a stack trace).
T9="$(mktemp -d)"; ( cd "$T9" && git init -q ) && mkdir -p "$T9/src"
printf "const STATUSES = [\n  { type: 'lead', active: 'true' },\n  { type: 'lead', active: 'true' },\n  { type: 'lead', active: 'true' }\n];\n" > "$T9/src/a.ts"
printf "const STAGES = [\n  { type: 'lead', active: 'true' },\n  { type: 'lead', active: 'true' },\n  { type: 'lead', active: 'true' }\n];\n" > "$T9/src/b.ts"
( cd "$T9" && python3 "$KIT/scripts/check_guess_lists.py" >/dev/null 2>&1 ); check "S-05 green: object-array with no discernible stable key does not crash or false-flag" 0 $?
rm -rf "$T9"

# Same identifying key name, one value drifted — must not be unified. Exact
# fingerprint matching only, same as the flat-string path; no fuzzy overlap.
T10="$(mktemp -d)"; ( cd "$T10" && git init -q ) && mkdir -p "$T10/src"
printf "const CUSTOM_OBJECTS = [\n  { label: 'Communities', objectKey: 'custom_objects.communities' },\n  { label: 'Site Maps', objectKey: 'custom_objects.site_maps' },\n  { label: 'Community Residents', objectKey: 'custom_objects.community_residents' }\n];\n" > "$T10/src/a.ts"
printf "const CUSTOM_OBJECTS = [\n  { label: 'Communities', objectKey: 'custom_objects.communities' },\n  { label: 'Site Maps', objectKey: 'custom_objects.site_maps' },\n  { label: 'Site Visits', objectKey: 'custom_objects.site_visits' }\n];\n" > "$T10/src/b.ts"
( cd "$T10" && python3 "$KIT/scripts/check_guess_lists.py" >/dev/null 2>&1 ); check "S-05 green: object-arrays with one drifted objectKey value are not falsely unified" 0 $?
rm -rf "$T10"

# fail-loud (G-03): a file that cannot even be read (dangling symlink) must
# not crash the scan or mask a real duplicate elsewhere in the same walk —
# matches the pre-existing open()-failure try/except-continue this gate
# already had for the flat-string path.
T11="$(mktemp -d)"; ( cd "$T11" && git init -q ) && mkdir -p "$T11/src"
echo "const ROLES = ['admin', 'editor', 'viewer'];" > "$T11/src/a.ts"
echo "const PERMS = ['admin', 'editor', 'viewer'];" > "$T11/src/b.ts"
ln -s /nonexistent/target/does/not/exist.ts "$T11/src/broken.ts"
( cd "$T11" && python3 "$KIT/scripts/check_guess_lists.py" >/dev/null 2>&1 ); check "S-05 red: unreadable file (dangling symlink) does not crash and real duplicate still blocks" 1 $?
rm -rf "$T11"

# ---------- S-05 object-array entries separated by line comments (PR #35 review) ----------
# OBJARR_RE's old entry separator was bare `\s*,\s*` — a `//` comment sitting
# between one entry's comma and the next entry's `{` (`{ id: 'one' }, // first`)
# is not whitespace, so the whole array silently failed to match and the
# duplicate went unreported. Not a rare shape: hand-maintained lookup arrays
# get trailing per-entry comments *because* they are exactly the
# copy-pasted-across-files code S-05 exists to catch.
T12="$(mktemp -d)"; ( cd "$T12" && git init -q ) && mkdir -p "$T12/src"
printf "const CUSTOM_OBJECTS = [\n  { label: 'Communities', objectKey: 'custom_objects.communities' }, // first\n  { label: 'Site Maps', objectKey: 'custom_objects.site_maps' }, // second\n  { label: 'Community Residents', objectKey: 'custom_objects.community_residents' }, // third\n];\n" > "$T12/src/a.ts"
printf "const REPORTING_CUSTOM_OBJECTS = [\n  { label: 'Communities', objectKey: 'custom_objects.communities' }, // dup-a\n  { label: 'Site Maps', objectKey: 'custom_objects.site_maps' }, // dup-b\n  { label: 'Community Residents', objectKey: 'custom_objects.community_residents' }, // dup-c\n];\n" > "$T12/src/b.ts"
( cd "$T12" && python3 "$KIT/scripts/check_guess_lists.py" >/dev/null 2>&1 ); check "S-05 red: object-array duplicate with per-entry line comments blocks" 1 $?
rm "$T12/src/b.ts"
( cd "$T12" && python3 "$KIT/scripts/check_guess_lists.py" >/dev/null 2>&1 ); check "S-05 green: same line-commented shape in only 1 file does not block" 0 $?
rm -rf "$T12"

# ---------- S-05 object-array entries separated by block comments (PR #35 review) ----------
# Same gap, `/* ... */` form. One file below carries the comments and the
# other has none at all, to prove the fingerprint rides on the entries'
# values — never on the comment text, or on whether a comment is there.
T13="$(mktemp -d)"; ( cd "$T13" && git init -q ) && mkdir -p "$T13/src"
printf "const CUSTOM_OBJECTS = [\n  { label: 'Communities', objectKey: 'custom_objects.communities' }, /* first */\n  { label: 'Site Maps', objectKey: 'custom_objects.site_maps' }, /* second */\n  { label: 'Community Residents', objectKey: 'custom_objects.community_residents' } /* third */\n];\n" > "$T13/src/a.ts"
printf "const REPORTING_CUSTOM_OBJECTS = [\n  { label: 'Communities', objectKey: 'custom_objects.communities' },\n  { label: 'Site Maps', objectKey: 'custom_objects.site_maps' },\n  { label: 'Community Residents', objectKey: 'custom_objects.community_residents' }\n];\n" > "$T13/src/b.ts"
( cd "$T13" && python3 "$KIT/scripts/check_guess_lists.py" >/dev/null 2>&1 ); check "S-05 red: object-array duplicate with block comments on only one side still blocks" 1 $?
rm -rf "$T13"

# ---------- S-05 object-array with a comment leading the array (PR #35 review) ----------
# The reviewer's finding named "per-entry or leading comments" — this is the
# other shape: a comment sitting right after `[`, before the first entry,
# which the old `\[\s*` could not skip over either.
T14="$(mktemp -d)"; ( cd "$T14" && git init -q ) && mkdir -p "$T14/src"
printf "const CUSTOM_OBJECTS = [\n  // GHL custom object catalog\n  { label: 'Communities', objectKey: 'custom_objects.communities' },\n  { label: 'Site Maps', objectKey: 'custom_objects.site_maps' },\n  { label: 'Community Residents', objectKey: 'custom_objects.community_residents' }\n];\n" > "$T14/src/a.ts"
printf "const REPORTING_CUSTOM_OBJECTS = [\n  { label: 'Communities', objectKey: 'custom_objects.communities' },\n  { label: 'Site Maps', objectKey: 'custom_objects.site_maps' },\n  { label: 'Community Residents', objectKey: 'custom_objects.community_residents' }\n];\n" > "$T14/src/b.ts"
( cd "$T14" && python3 "$KIT/scripts/check_guess_lists.py" >/dev/null 2>&1 ); check "S-05 red: object-array duplicate with a comment leading the array still blocks" 1 $?
rm -rf "$T14"

# ---------- S-05 nested-object entries still fail closed (PR #35 review regression guard) ----------
# The comment-tolerance fix only loosens the separator BETWEEN entries; it
# must not loosen `[^{}]*` itself. An entry holding a nested object should
# still simply fail to match, exactly as documented above OBJARR_RE — green
# both before and after this fix, proving the conservative trade-off holds.
T15="$(mktemp -d)"; ( cd "$T15" && git init -q ) && mkdir -p "$T15/src"
printf "const CUSTOM_OBJECTS = [\n  { label: 'Communities', objectKey: 'custom_objects.communities', meta: { nested: true } },\n  { label: 'Site Maps', objectKey: 'custom_objects.site_maps', meta: { nested: true } },\n  { label: 'Community Residents', objectKey: 'custom_objects.community_residents', meta: { nested: true } }\n];\n" > "$T15/src/a.ts"
printf "const REPORTING_CUSTOM_OBJECTS = [\n  { label: 'Communities', objectKey: 'custom_objects.communities', meta: { nested: true } },\n  { label: 'Site Maps', objectKey: 'custom_objects.site_maps', meta: { nested: true } },\n  { label: 'Community Residents', objectKey: 'custom_objects.community_residents', meta: { nested: true } }\n];\n" > "$T15/src/b.ts"
( cd "$T15" && python3 "$KIT/scripts/check_guess_lists.py" >/dev/null 2>&1 ); check "S-05 green: object-array entries holding a nested object still fail to match (fail-closed, unchanged)" 0 $?
rm -rf "$T15"

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
