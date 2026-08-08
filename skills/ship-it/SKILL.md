---
name: ship-it
description: Prepare work for merge and release — run the right audit agents, check the Definition of Done, write the rollback step, bump the version, and update the changelog. Use when the user says "ship it", "ready to merge", "open the PR", "cut a release", or when a branch is finished and needs to go out.
---

# Ship It

## 1. Verify

Run the project verify command. If it fails, stop. Report the failing check, not a summary.

## 2. Audit agents

Run only what the diff touches:

| Diff touches | Agent |
|---|---|
| A migration | `schema-reviewer` |
| An external source or adapter | `integration-auditor` |
| A shared payload, event, or endpoint | `contract-drift-checker` |
| Always | `verify-runner` |

Report findings before proceeding. UNSAFE or BREAKING findings block the PR.

## 3. Definition of Done

Walk `${CLAUDE_PLUGIN_ROOT}/templates/process/DEFINITION.md`. Report each unmet item explicitly — never silently pass one.

## 4. Rollback

Write the actual undo path. Test the claim:
- Migration ran? Then "revert the commit" is false. Describe the real path.
- Feature-flagged? The rollback is the flag, and that's a good answer.
- Data written that a revert would orphan? Say so.

## 5. PR

```bash
git add -A
git commit -m "<type>(<scope>): <summary>"
git push -u origin <branch>
gh pr create --title "<type>(<scope>): <summary>" --body-file .github/pull_request_template.md
```

Fill the template from `templates/process/PR.template.md`. Link the spec or explain its absence.

## 6. Release, if this is one

- Bump the version per semver — a breaking API or payload change is major, no exceptions for "nobody's using it yet"
- Add a `CHANGELOG.md` entry written for a consumer, not a committer: what changed for them, and what they must do
- Tag after merge, never before

## 7. Work DB

The sync handles `State`, `PR URL`, `Branch`, `Commit`, and `Merged` on its own — do not write them.

Do write, if not already set:
- `Spec` and `ADR` URLs for anything this shipped against
- `Notes` — anything a future reader needs that the diff cannot tell them
- `Stage` → `Shipped`

Also set `Status: Shipped` on the spec file itself and append the merge commit SHA, so the spec points at exactly what fulfilled it.

## 8. After deploy

Confirm the health check is green and report it. If a migration ran, confirm it completed on the target. Do not declare shipped based on a merge.
