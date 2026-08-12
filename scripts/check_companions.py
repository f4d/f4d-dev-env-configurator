#!/usr/bin/env python3
"""
CP-01 — declared companion plugins are installed at the version declared.

A11 taught that a missing plugin silently removes every guard it carries, and
that absence reads as permission. Delegating work to a companion plugin
(superpowers, say) reintroduces exactly that failure one level up: the kit stops
restating a rule because the companion covers it, the companion is not
installed, and nothing covers it at all.

This closes that by making the expectation explicit and checkable.

NOT a CI gate. CI hosts have no Claude Code installation, so an absent plugin
registry means "not a Claude Code host", not "the companion is missing".
Treating those the same would fire on every CI run, and by A8 a gate that fires
wrongly gets disabled. Exit 0 with SKIP in that case; exit 1 only when the host
HAS a registry and the declaration is genuinely unmet.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import plugin_registry_path, repo_root  # noqa: E402

STATE = os.path.join(".claude", ".framework-state.json")


def die(msg):
    print(f"check_companions: ERROR: {msg}")
    raise SystemExit(1)


def parse_version(v):
    """'6.2.0' -> (6, 2, 0). Non-numeric segments sort as 0 rather than crash."""
    parts = []
    for seg in str(v).split(".")[:3]:
        digits = "".join(c for c in seg if c.isdigit())
        parts.append(int(digits) if digits else 0)
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts)


def declared(base):
    """The companions map from .framework-state.json, or {} when absent."""
    path = os.path.join(base, STATE)
    if not os.path.exists(path):
        return {}
    try:
        with open(path) as fh:
            state = json.load(fh)
    except (OSError, ValueError) as exc:
        # G-03: a guard that cannot evaluate its input must block, not allow.
        die(f"{STATE} is unreadable ({exc}). Cannot verify companions.")
    if not isinstance(state, dict):
        die(f"{STATE} must be a JSON object, got {type(state).__name__}")
    companions = state.get("companions", {})
    if not isinstance(companions, dict):
        die(f"{STATE}: 'companions' must be an object, got {type(companions).__name__}")
    return companions


def installed_versions(path):
    """{plugin_name: ((major, minor, patch), raw_version_string)} from Claude
    Code's registry.

    Keys there are 'name@marketplace' and each maps to a list of install
    records; keep the highest version seen for a given name.
    """
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        die(f"plugin registry at {path} is unreadable ({exc})")
    if not isinstance(data, dict):
        die(f"plugin registry at {path} must be a JSON object, got {type(data).__name__}")
    plugins = data.get("plugins") or {}
    if not isinstance(plugins, dict):
        die(f"plugin registry at {path}: 'plugins' must be an object, got {type(plugins).__name__}")
    found = {}
    for key, entries in plugins.items():
        name = key.split("@", 1)[0]
        for entry in entries or []:
            if not entry:
                continue
            if not isinstance(entry, dict):
                die(f"plugin registry at {path}: install record for '{name}' must be an object, got {type(entry).__name__}")
            raw = entry.get("version")
            if not raw:
                continue
            ver = parse_version(raw)
            if name not in found or ver > found[name][0]:
                found[name] = (ver, raw)
    return found


def main():
    base = repo_root()
    wanted = declared(base)
    if not wanted:
        print("check_companions: OK — no companion plugins declared (CP-01).")
        return 0

    # Normalise once, here, so every downstream read of a spec can assume a
    # dict without repeating `or {}`. `null` (no extra fields, just "declared")
    # is a legitimate spec and becomes {}; anything else that isn't a dict
    # (e.g. "superpowers": "latest") is a malformed declaration, not a spec
    # missing optional fields — die() rather than let it surface as an
    # AttributeError on what should be the success path (I2).
    wanted = {k: (v or {}) for k, v in wanted.items()}
    for name, spec in wanted.items():
        if not isinstance(spec, dict):
            die(f"{STATE}: companions.{name} must be an object or null, got {type(spec).__name__}: {spec!r}")

    registry = plugin_registry_path()
    if not os.path.exists(registry):
        print("check_companions: SKIP — no Claude Code plugin registry on this host.")
        print(f"  looked in: {registry}")
        print("  Not applicable here (CI, or a non-Claude-Code host). Not a violation.")
        return 0

    have = installed_versions(registry)
    problems = []
    for name in sorted(wanted):
        spec = wanted[name]
        need_raw = spec.get("min_version", "0.0.0")
        need = parse_version(need_raw)
        if name not in have:
            problems.append((name, "not installed", need_raw, spec))
        elif have[name][0] < need:
            problems.append((name, have[name][1], need_raw, spec))

    if not problems:
        names = ", ".join(f"{n}>={wanted[n].get('min_version', '0.0.0')}" for n in sorted(wanted))
        print(f"check_companions: OK — {len(wanted)} companion(s) satisfied: {names} (CP-01).")
        return 0

    print(f"CP-01 VIOLATIONS — declared companion plugins unmet ({len(problems)}):")
    for name, got, need, spec in problems:
        print(f"  {name}: installed {got}, requires >= {need}")
        why = spec.get("why")
        if why:
            print(f"      declared because: {why}")
        source = spec.get("source")
        if source:
            print(f"      install from: {source}")
    print()
    print("A rule delegated to an absent plugin is not enforced by anything (A11).")
    print("Either install the companion, or remove the declaration and re-state")
    print("the rule locally — but do not leave the declaration unmet.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
