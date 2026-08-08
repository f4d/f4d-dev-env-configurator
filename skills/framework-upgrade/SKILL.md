---
name: framework-upgrade
description: Move a project from an older f4d-kit version to the current one — diff its .claude/ against the plugin, classify each difference, apply what is safe, and surface conflicts. Use when a repo is behind on plugin version, when /project-audit reports drift, after the framework ships a new version, or when the user says "update the framework", "sync the rules", or "this repo is on an old version".
---

# Framework Upgrade

The framework's promise is *"we are always working on the same system."* Without
this skill that promise decays silently — every repo keeps working while slowly
diverging, and nobody notices because nothing breaks.

## Run the diff first, always

```bash
python3 "$CLAUDE_PLUGIN_ROOT/scripts/upgrade.py" --plugin "$CLAUDE_PLUGIN_ROOT"
```

Dry run by default. It classifies every managed file five ways:

| Class | Meaning | Action |
|---|---|---|
| `UNCHANGED` | Identical | none |
| `FRAMEWORK` | Plugin changed, project untouched | safe to apply |
| `LOCAL` | Project customized, plugin unchanged | **keep** — never overwrite |
| `CONFLICT` | Both changed | human decides |
| `NEW` | Plugin has a file the project lacks | offer, do not assume |
| `ORPHAN` | Plugin dropped a rule the project still holds | flag, never auto-delete |

## Apply

```bash
python3 "$CLAUDE_PLUGIN_ROOT/scripts/upgrade.py" --plugin "$CLAUDE_PLUGIN_ROOT" --apply
```

Writes `FRAMEWORK` only. Add `--accept-new` after reviewing what `NEW` would
install — a new module the project does not need is context cost on every turn.

## Conflicts

**Never resolve a conflict by taking the framework wholesale.** That silently
deletes a project-specific rule someone added for a reason, and the deletion is
invisible afterward.

For each conflict, ask: is the local change still wanted?
- **Yes** → merge the framework's addition into the local version by hand
- **No** → take the framework version and note the removal in `docs/log.md`
- **It generalizes** → run `/promote-rule` to lift it into the plugin, then take the framework version

## Orphans

A rule the plugin dropped but the project still holds. Usually means the rule was
demoted framework-wide but is still load-bearing here — or that it is genuinely
dead. Ask, then either keep it as a documented local rule or remove it with a note.

## After applying

1. Run the project verify command. An upgrade that breaks verify is not done.
2. Run `/project-audit` — specifically the registry-honesty check, since new rules
   may claim enforcement this repo has not wired.
3. Bump the pinned version and commit it on its own:
   ```bash
   git add .claude
   git commit -m "chore: upgrade f4d-kit to <version>"
   ```
   Its own commit, so a bad upgrade reverts cleanly without taking feature work with it.

## Cadence

Monthly, alongside `/project-audit`. A repo more than two minor versions behind
should be upgraded before any new feature work — otherwise you are writing code
against rules the framework no longer holds.
