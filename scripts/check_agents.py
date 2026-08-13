#!/usr/bin/env python3
"""
A20 / G-07 — every implied agent is actually on disk.

Agent selection is derived, not declared, and it is derived from the same
signal `/project-init` used to write the file in the first place: which
`.claude/rules/*.md` modules this project holds.

  `verify-runner`           unconditional — every PR runs it, regardless of stack
  `schema-reviewer`         iff `.claude/rules/database.md` is held
  `integration-auditor`     iff `.claude/rules/data-integration.md` is held
  `contract-drift-checker`  iff `.claude/rules/contracts.md` is held

That pairing is not invented here — `templates/process/ENFORCEMENT.md`'s
honest-audit table already states it (each of these three modules names the
agent that advisory-enforces it). This script just makes the pairing
checkable instead of merely written down.

Why this needs to exist: A11 taught that a hook path silently vanishing reads
as permission, not as a gap. An agent file is exactly as silent when it goes
missing — deleted, gitignored by mistake, dropped by a sparse checkout — and
until now nothing noticed. Same shape, one layer up, for agents instead of
hooks.

NOT a CI gate, for the same reason check_companions.py is not one: whether an
agent file belongs here is a function of whether this repo has adopted
f4d-kit **as a consumer**, which needs two signals together, not one:
`.claude/.framework-state.json` present AND `.claude/rules/` present. Neither
alone is sufficient — `.claude/rules/` alone false-positives on repos using
Claude Code's own native rules feature for unrelated content (review comment
r3771422153 on PR #34); `.claude/.framework-state.json` alone false-positives
on f4d-kit's own repo, which carries that file for a different reason (A18
self-opt-in) but has no `.claude/rules/` of its own — it is the plugin
*source*, not a consumer (found 2026-08-13, by running this script against
this repo, not by inspection). A repo that never adopted the kit as a
consumer should not fail a check that assumes it did — that would fire on
every unrelated repo's CI, and a gate that fires wrongly gets disabled (A8).
Exit 0 with SKIP unless both signals are present; exit 1 only when the kit is
adopted here and a required agent file is genuinely missing.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import repo_root  # noqa: E402

RULES_DIR = os.path.join(".claude", "rules")
AGENTS_DIR = os.path.join(".claude", "agents")
# Same relative path check_companions.py's STATE constant already uses as the
# kit's adoption marker — written only by /project-init, unlike .claude/rules/
# which Claude Code's own native rules feature can populate independently.
FRAMEWORK_STATE = os.path.join(".claude", ".framework-state.json")

# .claude/rules/<module file> -> .claude/agents/<agent file> it implies.
# Mirrors templates/process/ENFORCEMENT.md's honest-audit table.
MODULE_AGENT = {
    "database.md": "schema-reviewer.md",
    "data-integration.md": "integration-auditor.md",
    "contracts.md": "contract-drift-checker.md",
}
UNCONDITIONAL = ("verify-runner.md",)


def die(msg):
    print(f"check_agents: ERROR: {msg}")
    raise SystemExit(1)


def expected_agents(held_rules):
    """The agent filenames this project should hold, given which rules modules it holds."""
    agents = set(UNCONDITIONAL)
    for module_file, agent_file in MODULE_AGENT.items():
        if module_file in held_rules:
            agents.add(agent_file)
    return agents


def reason(agent_file):
    if agent_file in UNCONDITIONAL:
        return "unconditional — always wired, regardless of modules"
    for module_file, mapped in MODULE_AGENT.items():
        if mapped == agent_file:
            return f"selected because .claude/rules/{module_file} is held"
    return "selected"  # unreachable given expected_agents()'s construction


def main():
    base = repo_root()
    rules_dir = os.path.join(base, RULES_DIR)
    agents_dir = os.path.join(base, AGENTS_DIR)
    state_path = os.path.join(base, FRAMEWORK_STATE)

    # Adoption needs BOTH signals, not either alone — each one false-positives
    # on its own. .claude/rules/ alone (review r3771422153 on PR #34): Claude
    # Code's native rules feature lets any repo hold a .claude/rules/ full of
    # project-local, non-kit content, which the old check mistook for "kit
    # adopted" and then reported real agent files as falsely missing.
    # .claude/.framework-state.json alone: f4d-kit's own repo carries that
    # file too (A18 self-opts it into its own plugin-declared hooks — a
    # completely different reason than being a scaffolded consumer), and has
    # no .claude/rules/ of its own to derive an expected agent set from — it
    # is the plugin *source*, `templates/rules/` is what consumers copy from,
    # not a target `upgrade.py` diffs against. Discovered by actually running
    # this script against this repo post-merge, not by inspection: it failed
    # its own gate reporting `verify-runner.md` "missing" here, with no
    # `.claude/agents/` directory to hold it (found 2026-08-13). A genuine
    # scaffolded repo has `.claude/rules/` populated by the time it has
    # anything in `.claude/agents/` to check (SKILL.md step 4 precedes step
    # 7), so requiring both together costs real consumers nothing.
    # `os.path.exists`, not `os.path.isdir`, on rules_dir here deliberately —
    # "absent" must SKIP, but "present as a plain file" (corrupted) must still
    # reach the G-03 fail-loud die() just below, not get swallowed into a
    # silent skip alongside genuine absence.
    if not os.path.exists(state_path) or not os.path.exists(rules_dir):
        print(f"check_agents: SKIP — no {FRAMEWORK_STATE} and {RULES_DIR}/ together here; "
              "this repo has not adopted f4d-kit as a consumer.")
        return 0

    # G-03: "absent" (fine — zero rules modules held, so only the
    # unconditional floor applies) and "present but not a directory"
    # (corrupted — cannot evaluate) are different states and must not
    # collapse into the same lenient branch.
    if os.path.exists(rules_dir) and not os.path.isdir(rules_dir):
        die(f"{RULES_DIR} exists but is not a directory — cannot evaluate.")
    try:
        held_rules = set(os.listdir(rules_dir)) if os.path.isdir(rules_dir) else set()
    except OSError as exc:
        die(f"cannot list {RULES_DIR} ({exc})")

    expected = expected_agents(held_rules)

    if os.path.exists(agents_dir) and not os.path.isdir(agents_dir):
        die(f"{AGENTS_DIR} exists but is not a directory — cannot evaluate.")
    try:
        present = set(os.listdir(agents_dir)) if os.path.isdir(agents_dir) else set()
    except OSError as exc:
        die(f"cannot list {AGENTS_DIR} ({exc})")

    candidates = expected & present

    # os.listdir() reports a name whether it belongs to a file, a directory,
    # or anything else, and os.path.getsize() on a directory is normally
    # nonzero — so a stray `mkdir .claude/agents/verify-runner.md` passed
    # both the presence and empty-file checks below and printed OK while
    # Claude still had no usable agent definition (review r3771422162 on PR
    # #34). Check the type explicitly, before size, and keep it a distinct
    # finding from "empty": both are present-but-useless, but they are
    # different bugs with different fixes (rmdir vs. restoring content).
    not_file = {name for name in candidates
                if not os.path.isfile(os.path.join(agents_dir, name))}

    # A file that exists but is empty (a bad merge, a truncated write, an
    # accidental `touch`) is functionally as missing as an absent one — an
    # agent definition with no body has no instructions to run.
    empty = {name for name in candidates - not_file
             if os.path.getsize(os.path.join(agents_dir, name)) == 0}
    missing = sorted((expected - present) | not_file | empty)

    if not missing:
        print(f"check_agents: OK — {len(expected)} expected agent(s) present: "
              f"{', '.join(sorted(expected))} (A20).")
        return 0

    print(f"A20 VIOLATIONS — expected agent file(s) missing, empty, or not a file ({len(missing)}):")
    for name in missing:
        if name in not_file:
            path = os.path.join(agents_dir, name)
            state = "a directory, not a file" if os.path.isdir(path) else "present but not a regular file"
        elif name in empty:
            state = "empty"
        else:
            state = "missing"
        print(f"  .claude/agents/{name}: {state} — {reason(name)}")
    print()
    print("An agent file can disappear by deletion, a bad .gitignore entry, or a")
    print("sparse checkout, and nothing else catches it (A20 — the A11 shape one")
    print("layer up: absence reads as permission). Restore it from the plugin's")
    print("agents/ directory, or drop the rules module that implies it if the")
    print("concern genuinely no longer applies to this project.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
