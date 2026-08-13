# A18 — plugin-declared hooks fire in a real scaffolded-shape repo, 2026-08-12

Claude Code 2.1.220 (matches the CLI version BACKLOG.md's original A18
measurement was taken on), headless (`claude -p --permission-mode acceptEdits`).
Real plugin install, real target repos, real guard fire. The acceptance bar
for A18 is an `.enforcement-log` entry from a fired guard in a real scaffolded
repo — not a passing unit test — so this is that entry, paired with the
negative case that proves the opt-in gate, not luck, is what fired it.

## Setup

Two scratch git repos, standing in for "a repo this kit scaffolded" and "a
repo it never touched" — the two cases A18's fix has to tell apart:

```
opted-in/.claude/.framework-state.json   {"version": "1.23.0", "files": {}}
not-opted-in/                            (no .claude/ at all)
```

Plugin installed from a throwaway marketplace pointing at this PR's own
worktree (so the install reflects these changes, not the published 1.22.2),
then removed again after the run — the user's real `f4d-kit@f4d` installation
(pointing at the main checkout) was never touched:

```
$ claude plugin marketplace add <this-worktree-path>
✔ Successfully added marketplace: f4d-a18proof (declared in user settings)
$ claude plugin install f4d-kit@f4d-a18proof
✔ Successfully installed plugin: f4d-kit@f4d-a18proof (scope: user)
```

Confirmed the install is a real snapshot of the worktree, not the stale
1.22.2 cache from before this fix — `diff` against every file in `hooks/`
under `~/.claude/plugins/cache/f4d-a18proof/f4d-kit/1.23.0/` came back
identical, `hooks.json` included, and `grep hook_opted_in hooks/guard.sh`
in the cache found it.

## Positive case — opted in, guard fires, logs, and blocks for real

Headless session, cwd = `opted-in/`, prompted to write a fake secret to
`.env` via the Write tool:

```
$ claude -p --permission-mode acceptEdits <<< 'Use the Write tool right now to
  create a file named .env in the current directory with the exact contents:
  FOO=bar. Do this as your first tool call...'

The write was blocked by a project hook, so no file was created.

The `f4d-kit` guard hook (`[C-01]`) intercepts writes to `.env` — secret
material is off-limits in this repo. Hooks are enforcement, not advice, so
I'm not going to route around it with `Bash`/heredoc or a temp-file-then-move.

If you want the variable recorded, I can add `FOO=bar` to `.env.example`
instead — say the word and I'll do it.
```

`opted-in/.env` — **absent** (the write genuinely never happened, not just an
unhappy message):

```
$ ls opted-in/
.claude/  .git/
```

`opted-in/.claude/.enforcement-log` — **the acceptance-bar line**:

```
2026-08-12T23:21:00Z	C-01	[withheld — secret-class deny]
```

That is `hooks/hooks.json`'s `PreToolUse` entry resolving `${CLAUDE_PLUGIN_ROOT}`
(something a project's own `settings.json` cannot do — the whole reason A18
existed), `hook_opted_in()` reading `.claude/.framework-state.json` and
proceeding, `guard.sh` matching the `.env` pattern, and `log_deny` writing the
line — the entire chain, end to end, in a real Claude Code session.

## Negative case — same plugin, same prompt, never opted in: silent

Identical session, identical prompt, cwd = `not-opted-in/` (no
`.claude/.framework-state.json` — never scaffolded):

```
$ claude -p --permission-mode acceptEdits <<< '(same prompt)'

Created `.env` with contents `FOO=bar` in `.../not-opted-in/`.

One note worth flagging: this directory is a git repo with no `.gitignore`,
so `.env` will show up as untracked and could be committed accidentally.
```

```
$ ls not-opted-in/
.env  .git/  A18-SCRATCH-TARGET-NOTES.md      <- .claude/ was never created at all
$ cat not-opted-in/.env
FOO=bar
```

Same globally-installed plugin, same matching `PreToolUse` entry in
`hooks/hooks.json`, same `guard.sh` — and it did nothing, not even create a
`.claude/` directory, because `hook_opted_in()` found no
`.framework-state.json` and exited before reading stdin. This is the pairing
non-negotiable #2 asks for: the fix is not "guard.sh blocks more" in general,
it is "guard.sh blocks exactly the repos that opted in, and costs nothing —
no subprocess work beyond one `git rev-parse` and one `[ -f ]`, no telemetry —
everywhere else."

## Cleanup

```
$ claude plugin uninstall f4d-kit@f4d-a18proof
✔ Successfully uninstalled plugin: f4d-kit (scope: user)
$ claude plugin marketplace remove f4d-a18proof
✔ Successfully removed marketplace: f4d-a18proof
```

`~/.claude/plugins/known_marketplaces.json` and `installed_plugins.json`
diffed byte-identical to their pre-run content afterward (the real `f4d`
marketplace and `f4d-kit@f4d` install, both untouched throughout); the leftover
cache directory the uninstall left behind (`~/.claude/plugins/cache/f4d-a18proof/`)
was removed by hand. Scratch repos live under this session's scratchpad, outside
any git repo — disposable, not committed.

## Bounds

- This measures the mechanism (plugin-declared `hooks/hooks.json` +
  `hook_opted_in`), not a full `/project-init` interview run. The scratch
  `opted-in/` repo has the one file the gate actually reads
  (`.claude/.framework-state.json`) rather than a complete scaffold — which is
  the correct isolation for this proof: A18 is about whether the hook fires
  given that file, not about whether the interview writes it, which A4/A5
  already covers.
- Single guard (`guard.sh`, C-01) exercised live end-to-end. The other five
  hooks share the identical `hook_opted_in()` gate (same function, same call
  site pattern) and each has its own red-then-green pair in
  `tests/hooks_test.sh`'s new "A18 — global opt-in gate" section (13 cases) —
  not re-proven individually against a live session here, for the same reason
  A6's protocol did not re-run every rule through the live harness once the
  aggregation mechanism was established.
- One CLI version (2.1.220) — the same one BACKLOG.md's original bug
  measurement used, so this is a direct before/after on the same runtime.
