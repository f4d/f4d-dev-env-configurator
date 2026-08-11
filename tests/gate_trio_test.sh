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
T3b="$(mktemp -d)"; ( cd "$T3b" && git init -q && mkdir lib && python3 "$KIT/scripts/check_pure_imports.py" 2>&1 | grep -q "NOTE" ); check "S-07 states not-applicable (A8)" 0 $?
rm -rf "$T3" "$T3b"

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
