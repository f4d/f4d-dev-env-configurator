# Dev Project Environment — start here

This repo is **f4d-kit**: the reusable development and code product management
framework. It is a Claude Code plugin, installed into every other project repo.

## First five minutes

```bash
# 0. Restore executable bits — zip does not preserve them, and a hook that is
#    not executable fails SILENTLY. Run this first, always.
bash bootstrap.sh

# 1. Confirm the history came through
git log --oneline

# 2. Confirm everything still passes
bash tests/hooks_test.sh                      # expect: pass=24 fail=0
python3 scripts/check_statelessness.py        # expect: clean
python3 scripts/check_guess_lists.py          # expect: clean

# 3. Push it somewhere durable
gh repo create f4d/f4d-kit --private --source=. --push
```

## Where things are

| Question | File |
|---|---|
| **What's left to do?** | `docs/BACKLOG.md` ← **read this first** |
| Why is it built this way? | `docs/ARCHITECTURE_REVIEW.md` |
| What decisions were made? | `docs/decisions/` |
| What are the rules, and what enforces each? | `templates/rules/REGISTRY.md` |
| How does work flow? | `templates/process/LIFECYCLE.md` |
| What's the enforcement model? | `templates/process/ENFORCEMENT.md` |
| What ships, and how to install | `README.md` |
| What changed, version by version | `CHANGELOG.md` |

## Resuming work

`docs/BACKLOG.md` §6 has the priority order. Top unstarted code item is **A4 —
resumable interview**. Every backlog item carries why it matters, numbered build
steps, done-when criteria, and the files it touches, so it can be picked up
without re-deriving anything.

## Using it on another project

```bash
cd <that-project>
claude
# /plugin → add marketplace → point at this repo → install
# then: /repo-builder   (new)   or   /project-audit  (existing)
```

## Non-negotiables carried forward

1. Every guard gets a red-then-green proof — break it, see it fail, restore.
2. Every guard needs a fail-loud case for when it cannot evaluate its input.
3. Document a rule immediately; track its enforcement status separately.
4. Never promote a JUDGMENT rule to a check.
5. Evidence over recollection — run `scripts/session_report.py` before concluding a rule was ignored.
6. The registry must stay honest: any row claiming HOOK/TEST/GATE has that check wired.
7. Local customizations survive upgrades. Never resolve a CONFLICT by taking the framework wholesale.
