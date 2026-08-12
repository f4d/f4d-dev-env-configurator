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


SKIP_DIRS = (
    ".git", "node_modules", ".venv", "venv", "dist", "build",
    "__pycache__", ".next", "target",
)


def plugin_registry_path() -> str:
    """Absolute path to Claude Code's installed-plugin registry.

    Overridable via $CLAUDE_PLUGIN_REGISTRY so harnesses can point at a fixture
    instead of the developer's real installation.
    """
    override = os.environ.get("CLAUDE_PLUGIN_REGISTRY")
    if override:
        return override
    return os.path.expanduser("~/.claude/plugins/installed_plugins.json")
