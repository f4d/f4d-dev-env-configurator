---
id: core
always_apply: true
---
# Core

## Git
- Branch per unit of work: `git checkout -b <type>/<scope>-<desc>` where type is feat|fix|chore|refactor|docs
- Conventional commits: `type(scope): imperative summary`
- Never commit to main. Never force-push a shared branch. Never commit `.env`, keys, or credentials.
- Run the verify command before every commit. A failing verify is a blocked commit.

Full loop:
```
git checkout main
git pull origin main
git checkout -b feat/<scope>-<desc>
# work
<verify command>
git add -A
git commit -m "feat(<scope>): <summary>"
git push -u origin feat/<scope>-<desc>
gh pr create --fill
```

## Scope
- Change the smallest surface that solves the problem. Do not reformat, rename, or "clean up" files outside the task.
- If a fix requires touching more than three files, say so and confirm before proceeding.
- Never delete a test to make a build pass.

## Secrets
- Read config from environment only. Never inline a credential, never echo one, never write one to a fixture.
- `.env.example` is committed with keys and empty values. `.env` never is.
