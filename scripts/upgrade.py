#!/usr/bin/env python3
"""
A1 — framework upgrade path.

Diffs a project's .claude/ against the plugin's current templates and classifies
every difference. Project customizations must survive; that is what makes this
usable more than once.

  UNCHANGED   identical — nothing to do
  FRAMEWORK   plugin changed, project untouched     → safe to apply
  LOCAL       project customized, plugin unchanged  → keep, never overwrite
  CONFLICT    both changed                          → human decides
  NEW         plugin has a file the project lacks   → offer
  ORPHAN      project has a rule the plugin dropped → flag, do not delete

Default is a dry run. --apply writes only FRAMEWORK and accepted NEW.
"""
import argparse
import hashlib
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import repo_root  # noqa: E402

STATE = ".claude/.framework-state.json"


def digest(path):
    if not os.path.exists(path):
        return None
    return hashlib.sha256(open(path, "rb").read()).hexdigest()[:16]


def load_state(base):
    p = os.path.join(base, STATE)
    return json.load(open(p)) if os.path.exists(p) else {"version": None, "files": {}}


def save_state(base, version, files):
    p = os.path.join(base, STATE)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    json.dump({"version": version, "files": files}, open(p, "w"), indent=2, sort_keys=True)


def plugin_version(plugin):
    p = os.path.join(plugin, ".claude-plugin", "plugin.json")
    return json.load(open(p))["version"] if os.path.exists(p) else "unknown"


def classify(base, plugin, state):
    """Compare each managed file three ways: as-shipped-before, now-in-project, now-in-plugin."""
    rows = []
    src_root = os.path.join(plugin, "templates", "rules")
    dst_root = os.path.join(base, ".claude", "rules")

    plugin_files = set(os.listdir(src_root)) if os.path.isdir(src_root) else set()
    project_files = set(os.listdir(dst_root)) if os.path.isdir(dst_root) else set()

    for name in sorted(plugin_files | project_files):
        if not name.endswith(".md"):
            continue
        if name == "REGISTRY.md":
            # A2: the registry lives in the plugin only; projects hold a manifest
            # and render their view. A committed copy is drift, not a NEW offer.
            if name in project_files:
                rows.append(("STALE-REGISTRY", f".claude/rules/{name}",
                             "projects render from manifest.json now (A2) — this copy will drift; migrate and remove"))
            continue
        rel = f".claude/rules/{name}"
        baseline = state["files"].get(rel)
        proj = digest(os.path.join(dst_root, name))
        plug = digest(os.path.join(src_root, name))

        if proj is None:
            rows.append(("NEW", rel, "plugin has it, project does not"))
        elif plug is None:
            rows.append(("ORPHAN", rel, "plugin dropped it; project still holds it"))
        elif proj == plug:
            rows.append(("UNCHANGED", rel, ""))
        elif baseline is None:
            rows.append(("CONFLICT", rel, "no baseline recorded — cannot tell who changed it"))
        elif proj == baseline and plug != baseline:
            rows.append(("FRAMEWORK", rel, "plugin changed, project untouched"))
        elif proj != baseline and plug == baseline:
            rows.append(("LOCAL", rel, "project customized — will not overwrite"))
        else:
            rows.append(("CONFLICT", rel, "both changed since last sync"))
    return rows


def manifest_report(base, plugin):
    """A2 step 5 — reconcile the project's rule manifest against the plugin registry.

    New plugin rules surface as candidates (adoption is a decision, not a sync);
    a manifest ID missing from the registry is a broken reference (A9) and is
    returned so the caller can fail the run.
    """
    mpath = os.path.join(base, ".claude", "rules", "manifest.json")
    if not os.path.exists(mpath):
        return []
    from render_registry import load_manifest, parse_registry  # single source (S-05)
    rules, overrides = load_manifest(mpath)
    _, by_id = parse_registry(os.path.join(plugin, "templates", "rules", "REGISTRY.md"))
    broken = [r for r in rules if r not in by_id]
    new = sorted(set(by_id) - set(rules))
    print()
    print(f"registry manifest   {len(rules)} rules held, {len(overrides)} override(s)")
    if broken:
        print(f"  BROKEN     manifest references unknown ID(s): {', '.join(broken)}")
        print("             IDs are permanent (A9) — the manifest or the plugin version is wrong. Fix first.")
    if new:
        print(f"  NEW rules  in the plugin registry, not held by this project: {', '.join(new)}")
        print("             Review each against this project — adoption is a decision, not a sync.")
    return broken


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plugin", required=True, help="path to the f4d-kit plugin")
    ap.add_argument("--apply", action="store_true", help="write FRAMEWORK and NEW changes")
    ap.add_argument("--accept-new", action="store_true", help="also install NEW files")
    args = ap.parse_args()

    base = repo_root()
    state = load_state(base)
    newver = plugin_version(args.plugin)

    print(f"project  {base}")
    print(f"pinned   {state['version'] or '(never synced)'}")
    print(f"plugin   {newver}")
    print()

    rows = classify(base, args.plugin, state)
    counts = {}
    for kind, rel, why in rows:
        counts[kind] = counts.get(kind, 0) + 1
        if kind == "UNCHANGED":
            continue
        print(f"  {kind:<10} {rel}")
        if why:
            print(f"             {why}")

    print()
    print("  ".join(f"{k}={v}" for k, v in sorted(counts.items())))

    broken_refs = manifest_report(base, args.plugin)

    if counts.get("CONFLICT"):
        print()
        print("CONFLICTS need a human. For each, decide whether the local change is")
        print("still wanted, then re-run. Never resolve a conflict by taking the")
        print("framework wholesale — that silently deletes a project-specific rule")
        print("someone added for a reason.")

    if not args.apply:
        print()
        print("Dry run. Re-run with --apply to write FRAMEWORK changes.")
        return 1 if broken_refs else 0

    written = []
    for kind, rel, _ in rows:
        if kind == "FRAMEWORK" or (kind == "NEW" and args.accept_new):
            src = os.path.join(args.plugin, "templates", "rules", os.path.basename(rel))
            dst = os.path.join(base, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            written.append(rel)

    files = dict(state["files"])
    for kind, rel, _ in rows:
        if kind in ("UNCHANGED", "FRAMEWORK", "NEW", "LOCAL"):
            d = digest(os.path.join(base, rel))
            if d:
                files[rel] = d
    save_state(base, newver, files)

    print()
    print(f"Wrote {len(written)} file(s). Baseline recorded at {newver}.")
    print("Run the project verify command before committing.")
    return 1 if broken_refs else 0


if __name__ == "__main__":
    sys.exit(main())
