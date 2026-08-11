#!/usr/bin/env bash
# O4 tier 1 — mechanical conformance: the templates a scaffold is assembled
# from must actually compose. Catches the class the GHL-MCP audit hit in the
# kit itself: a spec that references pieces which do not exist, workflows that
# do not parse, and module manifests that do not resolve against the registry.
#
# Tier 2 (behavioral: agent-run scaffold per module combo, verify green on the
# empty scaffold, full-spec plan/execute parity, failing-verify-keeps-state) is
# documented in docs/acceptance/O4-protocol.md — it needs an agent, not bash.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }

echo "workflows parse"
for f in "$KIT"/templates/github/*.yml; do
  if python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$f" 2>/dev/null; then
    ok "$(basename "$f") parses"
  else bad "$(basename "$f") does not parse as YAML"; fi
done

echo "scaffold templates exist (and compose files parse)"
for f in docker-compose.yml.tmpl docker-compose.multi.yml.tmpl CLAUDE.md.tmpl gitignore.tmpl env.example.tmpl verify.yml.tmpl dev-reset.sh.tmpl nginx-lb.conf guard-local.sh; do
  if [ -s "$KIT/templates/scaffold/$f" ]; then ok "templates/scaffold/$f"; else bad "templates/scaffold/$f MISSING or empty"; fi
done
for f in docker-compose.yml.tmpl docker-compose.multi.yml.tmpl verify.yml.tmpl; do
  # A template's conformance property: it renders to valid YAML once every
  # {{TOKEN}} is filled — so fill them with dummies, then parse.
  if python3 -c "
import re, sys, yaml
src = open(sys.argv[1]).read()
yaml.safe_load(re.sub(r'\{\{[A-Z_]+\}\}', 'dummy', src))" "$KIT/templates/scaffold/$f" 2>/dev/null; then
    ok "$f renders to valid YAML"
  else bad "$f does not render to valid YAML"; fi
done

echo "executables are executable"
for f in "$KIT"/hooks/*.sh "$KIT"/templates/scaffold/guard-local.sh; do
  [ -x "$f" ] && ok "$(basename "$f") +x" || bad "$(basename "$f") not executable"
done

echo "every registry section resolves as a module manifest (with the always-on core)"
T="$(mktemp -d)"
section_failures=$(python3 - "$KIT" "$T" <<'PY'
import sys, json, subprocess
kit, tmp = sys.argv[1], sys.argv[2]
sys.path.insert(0, f"{kit}/scripts")
from render_registry import parse_registry
sections, _ = parse_registry(f"{kit}/templates/rules/REGISTRY.md")
always = {r for s in sections for r in s["rows"] if s["title"] in ("Core", "Guards", "Silent degradation")}
failures = 0
for s in sections:
    if not s["rows"]:
        continue
    json.dump({"rules": sorted(always | set(s["rows"])), "overrides": {}}, open(f"{tmp}/m.json", "w"))
    r = subprocess.run(["python3", f"{kit}/scripts/render_registry.py",
                        "--plugin", kit, "--manifest", f"{tmp}/m.json", "--validate"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        failures += 1
        print(f"SECTION-FAIL {s['title']}: {r.stderr.strip()}", file=sys.stderr)
print(failures)
PY
)
rm -rf "$T"
if [ "$section_failures" -eq 0 ]; then ok "all registry sections resolve as manifests"; else bad "$section_failures registry section manifest(s) failed to resolve"; fi

echo "spec references exist (the missing-piece class)"
refs=$(grep -ohE 'templates/[a-z]+/[A-Za-z0-9._-]+\.(md|yml|tmpl|sh|py|conf|json)' \
  "$KIT/skills/project-init/SKILL.md" "$KIT/skills/project-init/references/scaffold-spec.md" 2>/dev/null | sort -u)
missing=0; total=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  total=$((total+1))
  [ -e "$KIT/$f" ] || { bad "referenced by the init spec but missing: $f"; missing=$((missing+1)); }
done <<< "$refs"
[ "$missing" -eq 0 ] && ok "every templates/ path the init spec references exists ($total refs)"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
