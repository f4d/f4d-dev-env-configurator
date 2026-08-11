#!/usr/bin/env python3
"""
A2 — the registry as a rendered view, not a copied file.

A project holds .claude/rules/manifest.json:

  { "rules": ["C-01", "S-01", ...], "overrides": { "S-03": "TEST (ratchet)" } }

Rule text and status live in ONE place — the plugin's templates/rules/REGISTRY.md.
This script renders a project's registry view from its manifest on demand, so a
project never commits a REGISTRY.md copy that can drift.

  render_registry.py --manifest .claude/rules/manifest.json --plugin $CLAUDE_PLUGIN_ROOT
  render_registry.py --validate ...   # exit 2 on any broken reference, print nothing else

Fail-loud by doctrine (G-03): a missing file, an unknown ID, an override on a
rule the project does not hold, an empty rules list, or an unknown manifest key
is an error — never an empty rendering. An empty view that "worked" is S-01
committed by the tool that exists to prevent it.
"""
import argparse
import json
import os
import re
import sys

ROW = re.compile(r"^\|\s*([A-Z]{1,2}-\d{2})\s*\|")
HEADING = re.compile(r"^##\s+(.*)$")
ALLOWED_KEYS = {"rules", "overrides"}


def die(msg):
    print(f"render_registry: ERROR: {msg}", file=sys.stderr)
    sys.exit(2)


def load_manifest(path):
    if not os.path.exists(path):
        die(f"manifest not found: {path}")
    try:
        m = json.load(open(path))
    except Exception as e:  # noqa: BLE001 — any parse failure blocks identically
        die(f"manifest unparseable: {path}: {e}")
    unknown = set(m) - ALLOWED_KEYS
    if unknown:
        die(f"unknown manifest key(s) {sorted(unknown)} — a typo here would be silently ignored otherwise")
    rules = m.get("rules")
    if not isinstance(rules, list) or not rules:
        die("manifest holds no rules — a project without rules should not have a manifest")
    overrides = m.get("overrides", {})
    if not isinstance(overrides, dict):
        die("overrides must be an object of ID -> Today-status text")
    return rules, overrides


def parse_registry(path):
    """Return (ordered sections, id->(section, row-cells)). Sections keep their table headers."""
    if not os.path.exists(path):
        die(f"plugin registry not found: {path}")
    sections, by_id = [], {}
    current = None
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        h = HEADING.match(line)
        if h:
            current = {"title": h.group(1), "rows": []}
            sections.append(current)
            continue
        r = ROW.match(line)
        if r and current is not None:
            rid = r.group(1)
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) != 5:
                die(f"registry row for {rid} has {len(cells)} cells, expected 5 — format drift, refusing to guess")
            if rid in by_id:
                die(f"duplicate registry ID {rid} — IDs are permanent and unique (A9)")
            by_id[rid] = (current["title"], cells)
            current["rows"].append(rid)
    if not by_id:
        die(f"no registry rows parsed from {path} — format drift, refusing to render an empty registry")
    return sections, by_id


def manifest_problems(rules, overrides, by_id):
    """The COMPLETE manifest-reference validation, as a list of problems.

    Single source (S-05): render/--validate and upgrade.py reconciliation must
    reject exactly the same manifests — a manifest the audit rejects must never
    pass an upgrade.
    """
    problems = []
    unknown = [r for r in rules if r not in by_id]
    if unknown:
        problems.append(f"manifest references unknown rule ID(s): {', '.join(unknown)} — "
                        "IDs are permanent; a missing one means the manifest or the plugin version is wrong")
    dupes = {r for r in rules if rules.count(r) > 1}
    if dupes:
        problems.append(f"manifest lists ID(s) more than once: {', '.join(sorted(dupes))}")
    bad_overrides = [r for r in overrides if r not in rules]
    if bad_overrides:
        problems.append(f"override(s) on rule(s) the project does not hold: {', '.join(sorted(bad_overrides))}")
    return problems


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--manifest", default=".claude/rules/manifest.json")
    ap.add_argument("--plugin", default=os.environ.get("CLAUDE_PLUGIN_ROOT", ""))
    ap.add_argument("--validate", action="store_true", help="check references only; exit 2 on any break")
    args = ap.parse_args()

    if not args.plugin:
        die("--plugin not given and CLAUDE_PLUGIN_ROOT unset")
    rules, overrides = load_manifest(args.manifest)
    sections, by_id = parse_registry(os.path.join(args.plugin, "templates", "rules", "REGISTRY.md"))

    for problem in manifest_problems(rules, overrides, by_id):
        die(problem)

    if args.validate:
        print(f"render_registry: OK — {len(rules)} rules, {len(overrides)} overrides, all IDs resolve.")
        return 0

    held = set(rules)
    out = ["# Rule Registry — rendered view",
           "",
           f"Rendered from `{args.manifest}` against the plugin registry. Do not commit;",
           "the manifest is the source, this view is disposable.",
           ""]
    for sec in sections:
        rows = [r for r in sec["rows"] if r in held]
        if not rows:
            continue
        out.append(f"## {sec['title']}")
        out.append("")
        out.append("| ID | Rule | Should be | Today | Promote when |")
        out.append("|---|---|---|---|---|")
        for rid in rows:
            cells = list(by_id[rid][1])
            if rid in overrides:
                cells[3] = f"{overrides[rid]} *(project override)*"
            out.append("| " + " | ".join(cells) + " |")
        out.append("")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
