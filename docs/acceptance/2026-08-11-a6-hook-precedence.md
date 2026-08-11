# A6 hook precedence — empirical run, 2026-08-11

Claude Code 2.1.220, headless (`claude -p --settings <file> --permission-mode
acceptEdits`), scratch repo. Two PreToolUse hooks on the `Write` matcher: a
blocker (`exit 2`) and an allower (`exit 0`). A control run proves the harness
itself is valid before either precedence run is read.

```
CONTROL (allower only)  : file CREATED        <- hooks fire; Write works
A (blocker first)       : file BLOCKED/absent
B (blocker second)      : file BLOCKED/absent
```

**Contract, now evidence-backed:** any matching hook exiting 2 blocks the tool
call; a passing hook cannot override a blocking one; **order affects only which
message the user sees first, never the outcome**.

**Marker re-run (same day, after review):** both hooks append distinct markers
to a shared file. Result, both orders: `file=blocked markers=[A B]` — **both
hooks executed in both orders**; the runner does not short-circuit after a
block. "All matching hooks run" is now directly observed, not inferred from
outcomes.

Bounds: single `--settings` source carrying both hooks — this proves the
aggregation semantics (all matching hooks run; any block wins). Cross-source
merging (user + project + plugin all contributing hooks to one matcher) is per
the Claude Code settings documentation: hook arrays merge and all run — the
same aggregation this test exercised, but not independently re-proven here.
The bash harness cannot test aggregation (it is harness behavior, not hook
behavior); this protocol is the test, re-runnable in minutes.
