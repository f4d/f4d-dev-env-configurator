#!/usr/bin/env python3
"""
C-10 — instruction files may not lie about the rules.

The CI gate for instruction-file sync (spec 001, capability 2). Two failures,
one exit code:

  1. A rule module has malformed/missing frontmatter (`render_instructions.py
     --validate`) — the source itself is not trustworthy.
  2. Any tool's instruction file (CLAUDE.md / AGENTS.md / .cursor/rules/*.mdc /
     GEMINI.md when present) carries a managed block that disagrees with the
     modules, or is missing its block entirely (`render_instructions.py
     --check`).

Either is a hard fail (exit 2). The rule this enforces is "every AI tool reads
the same rulebook, and that rulebook is the modules." A drifted managed block is
a second source of truth by the back door.

Runs against `.claude/rules` in a scaffolded repo, or `templates/rules` when the
gate runs on the kit itself (dogfood). GEMINI.md is checked only if it exists —
it is interview-gated, so its absence is not drift.

Fail-loud (G-03): if it cannot locate a rules dir, that is an error, not a pass.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RENDER = os.path.join(HERE, "render_instructions.py")
BASE_TARGETS = ["CLAUDE.md", "AGENTS.md", ".cursor/rules/f4d-kit.mdc"]


def die(msg):
    print(f"check_instruction_honesty: ERROR: {msg} (C-10)", file=sys.stderr)
    sys.exit(2)


def main():
    root = os.environ.get("PROJECT_ROOT", ".")
    if os.path.isdir(os.path.join(root, ".claude", "rules")):
        rules_dir = os.path.join(root, ".claude", "rules")
    elif os.path.isdir(os.path.join(root, "templates", "rules")):
        rules_dir = os.path.join(root, "templates", "rules")  # the kit dogfooding itself
    else:
        die("no rules dir (.claude/rules or templates/rules) — cannot judge instruction honesty")

    targets = list(BASE_TARGETS)
    if os.path.exists(os.path.join(root, "GEMINI.md")):
        targets.append("GEMINI.md")  # present => it must stay in sync too

    common = ["--rules-dir", rules_dir, "--root", root]
    if subprocess.run([sys.executable, RENDER, *common, "--validate"]).returncode != 0:
        sys.exit(2)
    rc = subprocess.run([sys.executable, RENDER, *common,
                         "--targets", ",".join(targets), "--check"]).returncode
    if rc != 0:
        sys.exit(2)
    print(f"check_instruction_honesty: OK — source valid, {len(targets)} instruction file(s) in sync (C-10).")


if __name__ == "__main__":
    main()
