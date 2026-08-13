"""Shared leaf for f4d-kit check scripts.

Exists because check_guess_lists.py flagged `git rev-parse --show-toplevel`
duplicated across four scripts. S-05 says extract one dependency-free leaf both
sides import — never copy. Dogfooding that.
"""
import os
import subprocess

GIT_ROOT_CMD = ["git", "rev-parse", "--show-toplevel"]


def repo_root() -> str:
    """Absolute path to the repo root, or cwd when not in a git repo."""
    try:
        return subprocess.check_output(
            GIT_ROOT_CMD, text=True, stderr=subprocess.DEVNULL
        ).strip()
    except Exception:
        return os.getcwd()


# frozenset (not a tuple) deliberately: a scanner with a genuine extra need
# (e.g. check_raw_sql.py excluding migrations/db/sql) extends this via
# `SKIP_DIRS | {"extra", "dirs"}` — documented and additive, never a
# hand-copied duplicate. That is A21: this constant existed for exactly this
# purpose, and only one of seven scanners actually imported it.
SKIP_DIRS = frozenset({
    ".git", "node_modules", ".venv", "venv", "dist", "build",
    "__pycache__", ".next", "target",
})


def path_is_skipped(path: str) -> bool:
    """True if a directory component of `path` is in SKIP_DIRS or dot-prefixed.

    Mirrors the pruning rule every worktree walk applies via
    `dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not
    d.startswith(".")]` — but for a flat path string instead of a live
    os.walk, since there is no filesystem to prune when the path comes from
    `git ls-tree` against a ref that is not checked out.

    Only directory components are checked, never the filename itself — a
    walk's dirnames filter never touches `filenames`, so `.env` sitting at
    repo root is not "skipped" by this rule and neither is this path.
    `git ls-tree` paths always use `/` regardless of host OS.
    """
    return any(part in SKIP_DIRS or part.startswith(".") for part in path.split("/")[:-1])


def filter_skipped_paths(paths):
    """Flat path list (e.g. `git ls-tree -r --name-only <ref>` output)
    reduced to the same view a SKIP_DIRS/dot-dir-pruned worktree walk would
    produce.

    A21 made every worktree-side walk agree on SKIP_DIRS and dot-directories.
    It left every baseline-ref-side enumeration (paths read from a ref via
    `git ls-tree`, not a live walk) unfiltered, so a tracked file under a
    newly-skipped directory at BASE_REF could still be counted from the
    baseline while the worktree walk correctly ignored it — a false diff
    between two views of what should be the same repo. Run baseline path
    lists through this before comparing them against a worktree walk.
    """
    return [p for p in paths if not path_is_skipped(p)]


def plugin_registry_path() -> str:
    """Absolute path to Claude Code's installed-plugin registry.

    Overridable via $CLAUDE_PLUGIN_REGISTRY so harnesses can point at a fixture
    instead of the developer's real installation.
    """
    override = os.environ.get("CLAUDE_PLUGIN_REGISTRY")
    if override:
        return override
    return os.path.expanduser("~/.claude/plugins/installed_plugins.json")
