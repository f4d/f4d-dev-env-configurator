# Companion Plugins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a repo declare the companion plugins it expects — starting with `superpowers` — and verify they are actually installed, so the kit can delegate work to them without reintroducing the A11 silent-absence failure.

**Architecture:** `.claude/.framework-state.json` gains a `companions` map alongside the `version` it already records. A new `scripts/check_companions.py` compares that declaration against Claude Code's own plugin registry at `~/.claude/plugins/installed_plugins.json`. `/project-init` asks one interview question and writes the declaration; `/project-audit` reads it and reports drift. A registry row makes the delegation visible, so the kit never claims enforcement that lives in a plugin which may be absent.

**Tech Stack:** Python 3.12 standard library only (no dependencies — this repo has no manifest and must not gain one). Bash harnesses in the existing red-then-green style.

## Global Constraints

These are the kit's own working agreements (`docs/BACKLOG.md` §7). Every task's requirements implicitly include this section.

- **§7.1** Every guard gets a red-then-green proof before it counts. Break it, see it fail, restore. A guard that passed first run has proved nothing.
- **§7.2** Every guard needs a fail-loud case — what happens when it cannot evaluate its input.
- **§7.3** Document a rule immediately; track its enforcement status separately. `PROSE` on a mechanisable rule is debt with a ticket.
- **§7.4** Never promote a JUDGMENT rule to a check.
- **§7.6** The registry must stay honest. Any row claiming HOOK/TEST/GATE has that check actually wired.
- **§7.8** Rules budget ~400 lines per repo. Pruning is as important as adding.
- **S-05** Extract one dependency-free leaf both sides import — never copy. Use `scripts/_common.py`.
- **C-06** Commit subjects: `type(scope)!: subject`, **max 100 characters**.
- Python scripts live in `scripts/`, are executable-agnostic (invoked as `python3 scripts/x.py`), and import shared helpers from `_common.py`.

## Design decision recorded up front

**The companion check is NOT a CI gate.** CI runners have no Claude Code installation, so `~/.claude/plugins/installed_plugins.json` is absent there. That absence means *"not a Claude Code host"*, which is different from *"the companion is missing"*. Conflating them would make the gate fire on every CI run, and by A8 a gate that fires wrongly gets disabled.

So the script distinguishes three outcomes:

| Situation | Exit | Why |
|---|---|---|
| No plugin registry on this host | 0, `SKIP` | Not applicable — CI, or a non-Claude-Code host |
| Registry present, all companions satisfied | 0, `OK` | — |
| Registry present, companion missing or too old | 1, `VIOLATIONS` | The declaration is unmet |
| `.framework-state.json` is malformed | 1, `ERROR` | §7.2 — cannot evaluate means block |

## File Structure

| File | Responsibility |
|---|---|
| `scripts/check_companions.py` (create) | The whole check: read declaration, read host registry, compare, report |
| `scripts/_common.py` (modify) | Gains `plugin_registry_path()` — the one place the host registry path is named |
| `tests/companions_test.sh` (create) | Red-then-green harness for every branch above |
| `scripts/upgrade.py` (modify) | `save_state`/`load_state` carry `companions` through an upgrade without dropping it |
| `templates/rules/REGISTRY.md` (modify) | Row G-06, making the delegation honest |
| `skills/project-init/SKILL.md` (modify) | One interview question; scaffold writes the declaration |
| `skills/project-audit/SKILL.md` (modify) | Reads the declaration, reports drift, recommends the add |

---

### Task 1: The companion check script

**Files:**
- Create: `scripts/check_companions.py`
- Modify: `scripts/_common.py` (append `plugin_registry_path`)
- Test: `tests/companions_test.sh`

**Interfaces:**
- Consumes: `_common.repo_root() -> str` (exists today)
- Produces:
  - `_common.plugin_registry_path() -> str` — absolute path to the host's `installed_plugins.json`, honouring `$CLAUDE_PLUGIN_REGISTRY` for tests
  - `check_companions.installed_versions(path: str) -> dict[str, tuple[tuple[int, int, int], str]]` — each value pairs the parsed version with the raw string, so error messages can print `5.9.0` rather than `(5, 9, 0)`
  - `check_companions.parse_version(v: str) -> tuple[int, ...]`
  - `check_companions.declared(base: str) -> dict[str, dict]` — the `companions` map from framework-state

- [ ] **Step 1: Write the failing test**

Create `tests/companions_test.sh`:

```bash
#!/usr/bin/env bash
# Red-then-green harness for check_companions.py (CP-01).
# Same contract as the other harnesses: every branch is seen to fail before it
# counts, and the cannot-evaluate path blocks rather than allows (G-03).
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
check() { if [ "$2" -eq "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (expected exit $2, got $3)"; fi }

T="$(mktemp -d)"; ( cd "$T" && git init -q ); mkdir -p "$T/.claude"

writestate() { printf '%s' "$1" > "$T/.claude/.framework-state.json"; }
writereg()   { printf '%s' "$1" > "$T/registry.json"; }
run() { ( cd "$T" && CLAUDE_PLUGIN_REGISTRY="$T/registry.json" python3 "$KIT/scripts/check_companions.py" >/dev/null 2>&1 ); }

REG_OK='{"version":2,"plugins":{"superpowers@claude-plugins-official":[{"version":"6.2.0"}]}}'
REG_OLD='{"version":2,"plugins":{"superpowers@claude-plugins-official":[{"version":"5.9.0"}]}}'
REG_NONE='{"version":2,"plugins":{}}'

# GREEN: no declaration at all — nothing to verify.
writestate '{"version":"1.22.2","files":{}}'; writereg "$REG_OK"
run; check "no companions declared passes" 0 $?

# RED: declared, host has it but too old.
writestate '{"version":"1.22.2","files":{},"companions":{"superpowers":{"min_version":"6.2.0"}}}'
writereg "$REG_OLD"
run; check "red: installed version below min blocks" 1 $?

# GREEN: same declaration, host satisfies it.
writereg "$REG_OK"
run; check "green: satisfied declaration passes" 0 $?

# RED: declared, host does not have it at all.
writereg "$REG_NONE"
run; check "red: missing companion blocks" 1 $?

# SKIP: no host registry — CI. Not applicable is not a violation.
( cd "$T" && CLAUDE_PLUGIN_REGISTRY="$T/does-not-exist.json" python3 "$KIT/scripts/check_companions.py" >/dev/null 2>&1 )
check "skip: absent host registry is not a violation" 0 $?

# FAIL-LOUD (G-03): malformed state cannot be evaluated, so it blocks.
writestate '{"version":"1.22.2","companions":'; writereg "$REG_OK"
run; check "fail-loud: malformed framework-state blocks" 1 $?

# Message names the companion and both versions, so the fix is obvious.
writestate '{"version":"1.22.2","files":{},"companions":{"superpowers":{"min_version":"6.2.0"}}}'
writereg "$REG_OLD"
out=$( cd "$T" && CLAUDE_PLUGIN_REGISTRY="$T/registry.json" python3 "$KIT/scripts/check_companions.py" 2>/dev/null; true )
printf '%s' "$out" | grep -q "superpowers"; check "message names the companion" 0 $?
printf '%s' "$out" | grep -q "5.9.0"; check "message names the installed version" 0 $?
printf '%s' "$out" | grep -q "6.2.0"; check "message names the required version" 0 $?

rm -rf "$T"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the harness to verify it fails**

```bash
bash tests/companions_test.sh
```

Expected: FAIL — every case errors because `scripts/check_companions.py` does not exist yet. This is the red state; do not proceed until you have seen it.

- [ ] **Step 3: Add the shared path helper**

Append to `scripts/_common.py` (S-05 — the host registry path is named once, here, not in each caller):

```python
def plugin_registry_path() -> str:
    """Absolute path to Claude Code's installed-plugin registry.

    Overridable via $CLAUDE_PLUGIN_REGISTRY so harnesses can point at a fixture
    instead of the developer's real installation.
    """
    override = os.environ.get("CLAUDE_PLUGIN_REGISTRY")
    if override:
        return override
    return os.path.expanduser("~/.claude/plugins/installed_plugins.json")
```

- [ ] **Step 4: Write the check script**

Create `scripts/check_companions.py`:

```python
#!/usr/bin/env python3
"""
CP-01 — declared companion plugins are installed at the version declared.

A11 taught that a missing plugin silently removes every guard it carries, and
that absence reads as permission. Delegating work to a companion plugin
(superpowers, say) reintroduces exactly that failure one level up: the kit stops
restating a rule because the companion covers it, the companion is not
installed, and nothing covers it at all.

This closes that by making the expectation explicit and checkable.

NOT a CI gate. CI hosts have no Claude Code installation, so an absent plugin
registry means "not a Claude Code host", not "the companion is missing".
Treating those the same would fire on every CI run, and by A8 a gate that fires
wrongly gets disabled. Exit 0 with SKIP in that case; exit 1 only when the host
HAS a registry and the declaration is genuinely unmet.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import plugin_registry_path, repo_root  # noqa: E402

STATE = os.path.join(".claude", ".framework-state.json")


def die(msg):
    print(f"check_companions: ERROR: {msg}")
    raise SystemExit(1)


def parse_version(v):
    """'6.2.0' -> (6, 2, 0). Non-numeric segments sort as 0 rather than crash."""
    parts = []
    for seg in str(v).split(".")[:3]:
        digits = "".join(c for c in seg if c.isdigit())
        parts.append(int(digits) if digits else 0)
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts)


def declared(base):
    """The companions map from .framework-state.json, or {} when absent."""
    path = os.path.join(base, STATE)
    if not os.path.exists(path):
        return {}
    try:
        with open(path) as fh:
            state = json.load(fh)
    except (OSError, ValueError) as exc:
        # G-03: a guard that cannot evaluate its input must block, not allow.
        die(f"{STATE} is unreadable ({exc}). Cannot verify companions.")
    companions = state.get("companions", {})
    if not isinstance(companions, dict):
        die(f"{STATE}: 'companions' must be an object, got {type(companions).__name__}")
    return companions


def installed_versions(path):
    """{plugin_name: (major, minor, patch)} from Claude Code's registry.

    Keys there are 'name@marketplace' and each maps to a list of install
    records; keep the highest version seen for a given name.
    """
    try:
        with open(path) as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        die(f"plugin registry at {path} is unreadable ({exc})")
    found = {}
    for key, entries in (data.get("plugins") or {}).items():
        name = key.split("@", 1)[0]
        for entry in entries or []:
            raw = (entry or {}).get("version")
            if not raw:
                continue
            ver = parse_version(raw)
            if name not in found or ver > found[name][0]:
                found[name] = (ver, raw)
    return found


def main():
    base = repo_root()
    wanted = declared(base)
    if not wanted:
        print("check_companions: OK — no companion plugins declared (CP-01).")
        return 0

    registry = plugin_registry_path()
    if not os.path.exists(registry):
        print("check_companions: SKIP — no Claude Code plugin registry on this host.")
        print(f"  looked in: {registry}")
        print("  Not applicable here (CI, or a non-Claude-Code host). Not a violation.")
        return 0

    have = installed_versions(registry)
    problems = []
    for name in sorted(wanted):
        spec = wanted[name] or {}
        need_raw = spec.get("min_version", "0.0.0")
        need = parse_version(need_raw)
        if name not in have:
            problems.append((name, "not installed", need_raw, spec))
        elif have[name][0] < need:
            problems.append((name, have[name][1], need_raw, spec))

    if not problems:
        names = ", ".join(f"{n}>={wanted[n].get('min_version', '0.0.0')}" for n in sorted(wanted))
        print(f"check_companions: OK — {len(wanted)} companion(s) satisfied: {names} (CP-01).")
        return 0

    print(f"CP-01 VIOLATIONS — declared companion plugins unmet ({len(problems)}):")
    for name, got, need, spec in problems:
        print(f"  {name}: installed {got}, requires >= {need}")
        why = spec.get("why")
        if why:
            print(f"      declared because: {why}")
        source = spec.get("source")
        if source:
            print(f"      install from: {source}")
    print()
    print("A rule delegated to an absent plugin is not enforced by anything (A11).")
    print("Either install the companion, or remove the declaration and re-state")
    print("the rule locally — but do not leave the declaration unmet.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 5: Run the harness to verify it passes**

```bash
bash tests/companions_test.sh
```

Expected: `pass=9 fail=0` — the harness in Step 1 contains nine `check()` calls. If you count differently, report the number you actually get; never edit the harness to hit a stated total.

- [ ] **Step 6: Confirm it is clean against this repo**

```bash
python3 scripts/check_companions.py
```

Expected: `check_companions: OK — no companion plugins declared (CP-01).` and exit 0 — the kit declares none yet. Task 4 changes that.

- [ ] **Step 7: Confirm no other harness regressed**

```bash
for t in hooks render_registry gate_trio statelessness conformance; do bash "tests/${t}_test.sh" | tail -1; done
```

Expected: `pass=40 fail=0`, `pass=11 fail=0`, `pass=39 fail=0`, `pass=4 fail=0`, `pass=29 fail=0`

- [ ] **Step 8: Commit**

```bash
git add scripts/check_companions.py scripts/_common.py tests/companions_test.sh
git commit -m "feat: CP-01 gate — declared companion plugins must be installed"
```

---

### Task 2: Carry the declaration through an upgrade

**Files:**
- Modify: `scripts/upgrade.py:36-48` (`load_state`, `save_state`)
- Test: `tests/companions_test.sh` (append)

**Interfaces:**
- Consumes: `check_companions.declared` (Task 1) reads the key this task must stop destroying
- Produces: `upgrade.save_state(base, version, files, registry_ids=None, companions=None)` — same call signature as today plus one optional keyword, so existing call sites keep working

**Why this is its own task:** `save_state` currently rebuilds the payload from scratch (`payload = {"version": version, "files": files}`), so it silently drops any key it does not know about. Run `upgrade.py --apply` once and the companion declaration vanishes — the check from Task 1 then passes for the wrong reason.

- [ ] **Step 1: Write the failing test**

Append to `tests/companions_test.sh`, immediately before the `rm -rf "$T"` line:

```bash
# An upgrade must not destroy the declaration. save_state rebuilds the payload
# from scratch, so an unknown key is dropped unless it is carried deliberately.
writestate '{"version":"1.0.0","files":{},"companions":{"superpowers":{"min_version":"6.2.0"}}}'
( cd "$T" && python3 - "$KIT" <<'PY' >/dev/null 2>&1
import sys, os
sys.path.insert(0, os.path.join(sys.argv[1], "scripts"))
import upgrade
state = upgrade.load_state(".")
upgrade.save_state(".", "1.22.2", state.get("files", {}), companions=state.get("companions"))
PY
)
python3 -c "import json,sys; sys.exit(0 if json.load(open('$T/.claude/.framework-state.json')).get('companions',{}).get('superpowers') else 1)"
check "upgrade preserves the companion declaration" 0 $?
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash tests/companions_test.sh
```

Expected: FAIL on `upgrade preserves the companion declaration` — `save_state` does not accept a `companions` keyword yet, so the heredoc raises `TypeError` and the declaration is never written.

- [ ] **Step 3: Make save_state carry it**

In `scripts/upgrade.py`, replace `save_state` (currently lines 42-48) with:

```python
def save_state(base, version, files, registry_ids=None, companions=None):
    p = os.path.join(base, STATE)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    payload = {"version": version, "files": files}
    if registry_ids is not None:
        payload["registry_ids"] = sorted(registry_ids)
    # An upgrade must not silently drop a declaration it did not author.
    # This payload is rebuilt from scratch every time, so anything not named
    # here disappears — and a companion declaration that vanishes makes CP-01
    # pass for the wrong reason.
    if companions:
        payload["companions"] = companions
    json.dump(payload, open(p, "w"), indent=2, sort_keys=True)
```

- [ ] **Step 4: Make the caller pass it through**

`scripts/upgrade.py` has exactly one call site, line 197. `state` is already in scope there (line 196 reads `state.get("registry_ids")`). Replace:

```python
    save_state(base, newver, files, registry_ids)
```

with:

```python
    save_state(base, newver, files, registry_ids, companions=state.get("companions"))
```

- [ ] **Step 5: Run the harness to verify it passes**

```bash
bash tests/companions_test.sh
```

Expected: `pass=10 fail=0` — nine assertions from Task 1 plus this one.

**The assertion must fail before the fix, and you must see it do so.** Checking only that `companions.superpowers` survives is not enough: `writestate` seeds that key directly, and a pre-fix run raises `TypeError` at the call boundary so `save_state` never writes at all — leaving the seeded value in place and the check green. Assert `version == "1.22.2"` as well, which only a real write can produce. Prove it by reverting `save_state` to its pre-fix form, running the harness, and capturing the failure.

- [ ] **Step 6: Commit**

```bash
git add scripts/upgrade.py tests/companions_test.sh
git commit -m "fix: upgrade must not drop the companion declaration it did not author"
```

---

### Task 3: Make the delegation honest in the registry

**Files:**
- Modify: `templates/rules/REGISTRY.md` (Guards section, after the `G-05` row at line ~53)

**Files (amended):**
- Modify: `templates/rules/REGISTRY.md` (Guards section, after `G-05`)
- Modify: `.github/workflows/gates.yml` and `.github/workflows/main-verify.yml` — add `companions` to each harness loop

**Interfaces:**
- Consumes: `tests/companions_test.sh` from Tasks 1–2 — the row may only claim `TEST` because that harness exists, passes, **and runs in CI as of this task**
- Produces: rule ID `G-06`, referenced by Tasks 4 and 5

**Sequencing note (corrected after review):** the CI wiring was originally Task 5's Step 5. Review found that left `G-06` claiming `**TEST** … done` for two commits while nothing automated ran the harness — a live §7.6 violation, and the exact failure the row itself describes. §7.3 says document a rule and wire its enforcement together, so the wiring belongs here. Never mark a row `done` in an earlier commit than the check it claims.

**Why this is its own task:** §7.6 says a row claiming enforcement must have that check wired. Writing the row before Task 1 exists would make the registry dishonest; writing it after is what makes the delegation visible. A reviewer could accept the script and still reject the rule's wording.

- [ ] **Step 1: Add the row**

In `templates/rules/REGISTRY.md`, in the `## Guards` table, add after the `G-05` row:

```markdown
| G-06 | A rule delegated to a companion plugin is only enforced while that plugin is installed | TEST | **TEST** (`tests/companions_test.sh`) | done |
```

- [ ] **Step 2: Verify the registry still parses**

```bash
bash tests/render_registry_test.sh
bash tests/conformance_test.sh
```

Expected: `pass=11 fail=0` and `pass=29 fail=0`. The conformance suite validates that every registry section resolves as a module manifest, so a malformed row fails here.

- [ ] **Step 3: Verify the new ID resolves**

```bash
python3 -c "
import sys; sys.path.insert(0, 'scripts')
from render_registry import parse_registry
_, by_id = parse_registry('templates/rules/REGISTRY.md')
print('G-06' in by_id and by_id['G-06'])
"
```

Expected: prints the parsed row, not `False`. A9 makes IDs permanent, so a row that does not resolve is a broken reference in every project manifest that later adopts it.

- [ ] **Step 4: Wire the harness into CI — this is what makes the row honest**

In **both** `.github/workflows/gates.yml` (the `harnesses` job) and `.github/workflows/main-verify.yml` (the `Harnesses` step), add `companions` to the end of the loop list:

```bash
          for t in hooks render_registry gate_trio statelessness conformance companions; do
```

Update the `gates.yml` job `name:` so its count stays truthful — it reads "123 tests across 5 suites"; with companions it is **133 tests across 6 suites** (40+11+39+4+29+10).

Do **not** add `scripts/check_companions.py` to either file's python `gates` list. It would exit 0 with `SKIP` on every CI run (no plugin registry on a CI host), and a check that always skips reads as a check that always passes. Only the harness goes to CI — it drives the script with fixture registries via `$CLAUDE_PLUGIN_REGISTRY`, so it works anywhere.

Verify:

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/gates.yml')); yaml.safe_load(open('.github/workflows/main-verify.yml')); print('YAML OK')"
for t in hooks render_registry gate_trio statelessness conformance companions; do printf "%-18s " "$t"; bash "tests/${t}_test.sh" | tail -1; done
```

Expected: `YAML OK`, then 40 / 11 / 39 / 4 / 29 / 10, all `fail=0`.

- [ ] **Step 5: Commit**

```bash
git add templates/rules/REGISTRY.md .github/workflows/gates.yml .github/workflows/main-verify.yml
git commit -m "docs: G-06 — delegated rules are enforced only while the plugin is present"
```

---

### Task 4: Ask for it in the interview

**Files:**
- Modify: `skills/project-init/SKILL.md` — the question table (around line 112), the plan preview block (around line 133), and the scaffold output list (step 7, around line 190)

**Interfaces:**
- Consumes: `G-06` (Task 3); the `companions` schema from Task 2
- Produces: `.claude/.framework-state.json` containing `companions`, which Task 5's audit check reads

**Why this is its own task:** it is a UX judgment — what to ask, whether it defaults on, and what the plan preview shows. A reviewer could approve the gate and the registry row while rejecting the wording of the question.

- [ ] **Step 1: Add the interview question**

In `skills/project-init/SKILL.md`, in the question table that currently ends with the `Q8` row, add:

```markdown
| Always | **Which companion plugins should this repo expect?** Default: `superpowers` (MIT, multi-harness — ships `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`; process skills for TDD, planning, debugging, code review). Offered, never imposed — a declaration is a promise the audit will check. | `companions` |
```

- [ ] **Step 2: Show it in the plan preview**

In the same file, in the fenced plan-preview block, add a line after `AGENTS:` so the user approves the declaration rather than discovering it:

```
COMPANIONS: superpowers >= 6.2.0   (declared; /project-audit will verify it stays installed)
```

- [ ] **Step 3: Write it during scaffold**

In the scaffold output list, extend item 7 so the declaration is written with the state, not left implicit:

```markdown
7. `.claude/agents/*.md` — only the selected agents. Also record the interview's companion answer in `.claude/.framework-state.json` as `"companions": {"<name>": {"min_version": "<v>", "why": "<one line>", "source": "<marketplace or URL>"}}`. Declare only what the project genuinely relies on: G-06 means an unmet declaration is a finding, so declaring a plugin nobody uses manufactures a permanent false alarm. Verify with `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/check_companions.py"` before finishing.
```

- [ ] **Step 4: Verify the skill still conforms**

```bash
bash tests/conformance_test.sh
```

Expected: `pass=29 fail=0`. This suite checks that every spec-referenced template exists, so a reference to a missing file fails here.

- [ ] **Step 5: Commit**

```bash
git add skills/project-init/SKILL.md
git commit -m "feat: interview asks which companion plugins the repo expects"
```

---

### Task 5: Check it during audit

**Files:**
- Modify: `skills/project-audit/SKILL.md` — the "Framework version" checks block, and the "Adoption recommendation" section

**Interfaces:**
- Consumes: the `companions` declaration written by Task 4; `scripts/check_companions.py` from Task 1
- Produces: nothing downstream — this is the last task

**Why this is its own task:** the audit is where a *missing* companion becomes a recommendation with a danger column, which is a different judgment from the interview's. A reviewer could approve the question and reject the recommendation's framing.

- [ ] **Step 1: Add the presence check**

In `skills/project-audit/SKILL.md`, in the **Framework version** bullet list, add after the "Confirm the plugin is actually installed" bullet:

```markdown
- **Check declared companions.** Run `python3 "$CLAUDE_PLUGIN_ROOT/scripts/check_companions.py"` from the target's root. A declaration in `.claude/.framework-state.json` that the host does not satisfy is a finding (G-06): every rule the project stopped stating because a companion covered it is now enforced by nothing. A `SKIP` result means this host has no plugin registry — report it as not-checked, never as a pass.
```

- [ ] **Step 2: Add the suggested-add path for repos with no declaration**

In the same file, in the **Adoption recommendation** section, add:

```markdown
When the repo declares no companions, say so and consider recommending `superpowers` (MIT, multi-harness) as a **suggested add, never an assumed one**. It supplies process skills — TDD, planning, systematic debugging, code review — that the kit currently restates in prose. **Danger:** it wires its own `SessionStart` hook and adds roughly 3 KB of always-on context plus fourteen skill descriptions, against the ~400-line rules budget (§7.8); and adopting it without a G-06 declaration recreates A11 one level up. Recommend the declaration and the plugin together, or neither.
```

- [ ] **Step 3: Verify conformance**

```bash
bash tests/conformance_test.sh
```

Expected: `pass=29 fail=0`

- [ ] **Step 4: Full verification ritual**

```bash
for t in hooks render_registry gate_trio statelessness conformance companions; do printf "%-18s " "$t"; bash "tests/${t}_test.sh" | tail -1; done
for g in check_statelessness check_guess_lists check_catch_empty check_log_hygiene check_companions; do printf "%-22s " "$g"; python3 "scripts/$g.py" >/dev/null 2>&1 && echo clean || echo FINDINGS; done
```

Expected: all harnesses pass, all five gates clean.

- [ ] **Step 5: Commit**

```bash
git add skills/project-audit/SKILL.md
git commit -m "feat: audit verifies declared companions, recommends superpowers as an add"
```

*(The CI wiring that was originally this task's Step 5 moved to Task 3 — a registry row may not claim `done` in an earlier commit than the check it names. See Task 3's sequencing note.)*

---

## Self-review

**Spec coverage.** The four asks were: declare companions in framework-state (Task 2 schema + Task 4 writes it), an interview option (Task 4), a suggested add when missing at audit (Task 5), and registry honesty for delegated rules (Task 3). All covered. The fifth idea raised in discussion — *pruning* kit doctrine that superpowers already covers, e.g. §7.1 red-then-green against `test-driven-development` — is **deliberately out of scope**: it changes what the kit teaches rather than what it verifies, and it should not ride along with the mechanism that makes delegation safe. It needs its own plan, after G-06 exists and a real repo has run with a declaration.

**Placeholder scan.** No TBDs. Every code step carries the actual content, including exact before/after text for the single `save_state` call site (verified: `scripts/upgrade.py:197`, with `state` in scope from line 196).

**Type consistency.** `parse_version` returns a 3-tuple everywhere. `installed_versions` returns `{name: (tuple, raw_string)}` — the raw string is kept so error messages can print `5.9.0` rather than `(5, 9, 0)`, and both Task 1's message assertions and the reporting loop rely on that shape. `declared` returns a plain dict, and `main` treats a per-companion value as a dict with optional `min_version`/`why`/`source` keys — matching what Task 4 tells the scaffolder to write.
