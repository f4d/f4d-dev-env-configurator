#!/usr/bin/env python3
"""
S-05 — one canonical resolver per question.

Two hardcoded lists answering the same question will disagree, and the
disagreement surfaces as a blank rather than a conflict. This finds duplicate
constant collections across modules — both flat literal collections
(`["admin", "editor", "viewer"]`) and array-of-object literals that repeat an
identifying key across files (A17: GHL-MCP's six-file `CUSTOM_OBJECTS`, each
file redeclaring its own array of objects keyed by the same `objectKey`
values).

Heuristic and deliberately conservative: flags only near-identical literal
collections of 3+ string members appearing in 2+ files. The object-array path
is name-agnostic like the flat-string path: it never looks for "objectKey"
literally, only for a per-entry property whose values are distinct within
their own array (i.e. behaves like an identifying key), then fingerprints on
those values exactly like a flat list would.

Exit 1 on any duplicate. Exit 0 clean.
"""
import os
import re
import subprocess
import sys
from collections import defaultdict

EXT = (".py", ".ts", ".tsx", ".js", ".jsx")

# Two hardcoded "how many members make this worth flagging" floors would
# itself be an S-05 violation — one canonical threshold, shared by the
# flat-string and object-array paths below.
MIN_MEMBERS = 3

LIST_RE = re.compile(r"[\[\(]\s*((?:['\"][A-Za-z0-9_\- ]{2,40}['\"]\s*,\s*){2,}['\"][A-Za-z0-9_\- ]{2,40}['\"])\s*,?\s*[\]\)]")

# Array-of-flat-object literals: `[ {...}, {...}, ... ]`. `[^{}]*` deliberately
# refuses to span a brace, so an entry holding a nested object (e.g.
# `{ id: 'x', meta: { a: 1 } }`) simply fails to match rather than being
# mis-parsed — the same "deliberately conservative" trade-off LIST_RE already
# makes for brackets it cannot follow.
#
# Entries are commonly hand-annotated (`{ id: 'one' }, // first`), so every
# gap that whitespace alone used to own — before the first entry, around each
# comma, after the last entry — also tolerates `//` line comments and
# `/* */` block comments, mixed in with whitespace in any order. Same
# conservative bar as `[^{}]*` above: this is not a tokenizer, so a nested
# block comment, a `*/` hiding inside a string literal, or a comment
# containing a stray brace is not handled — any of those just fails to
# match, the same "skipped, not mis-parsed" fallback the rest of this file
# already relies on.
GAP = r"(?:\s|//[^\n]*|/\*.*?\*/)*"
OBJARR_RE = re.compile(
    r"\[" + GAP + r"((?:\{[^{}]*\}" + GAP + r"," + GAP + r"){1,}"
    r"\{[^{}]*\}" + GAP + r",?" + GAP + r")\]",
    re.DOTALL,
)
ENTRY_RE = re.compile(r"\{[^{}]*\}")
# Object-member values may carry dots (`custom_objects.communities`) that flat
# list members never needed to — a namespaced identifier is the common shape
# of a real key column.
KV_RE = re.compile(r"['\"]?([A-Za-z_$][A-Za-z0-9_$]*)['\"]?\s*:\s*['\"]([A-Za-z0-9_.\- ]{2,40})['\"]")


sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import SKIP_DIRS, repo_root as root  # noqa: E402

# Additive (A21): fixture/test-data dirs are not source under S-05's remit —
# extend the shared skip set rather than hand-copy it. This is the scanner
# that flagged the original SKIP-tuple duplication (see _common.py); it must
# not itself keep a hand-rolled copy.
SKIP = SKIP_DIRS | {"fixtures", "__fixtures__", "testdata"}


def object_array_fingerprints(text):
    """Yield (key, sorted_value_tuple) for each array-of-object literal that
    has a per-entry property behaving like an identifying key.

    Name-agnostic on purpose (A17): nothing here looks for "objectKey", or
    any other name, literally. A property qualifies purely on shape —
    present on every entry, a plain string, and distinct across entries
    within its own array. A value repeated across entries (e.g. a `type` or
    `status` column) reads as categorical, not identifying, and is dropped —
    the main lever keeping this conservative, since without it any common
    column would qualify. GHL-MCP's real `CUSTOM_OBJECTS` arrays each have
    multiple qualifying columns (`label`, sometimes `objectId`, `objectKey`);
    every one is fingerprinted independently, exactly as two equal-valued
    flat lists would be regardless of what either was called.

    Never raises: a malformed or deeply-nested array just fails to match and
    yields nothing, the same fail-soft contract LIST_RE already has for
    brackets it cannot follow — a stable-key-less array is reported as
    "nothing found" rather than crashing the whole gate (G-03).
    """
    try:
        for arr in OBJARR_RE.finditer(text):
            entries = ENTRY_RE.findall(arr.group(1))
            if len(entries) < MIN_MEMBERS:
                continue
            per_entry = [dict(KV_RE.findall(e)) for e in entries]
            common_keys = set(per_entry[0]) if per_entry else set()
            for kv in per_entry[1:]:
                common_keys &= set(kv)
            for key in sorted(common_keys):
                values = [kv[key] for kv in per_entry]
                # CLI argument arrays are not guess lists about domain values.
                if any(v.startswith("-") for v in values):
                    continue
                if len(set(values)) != len(values):
                    continue  # repeats -> categorical column, not a key
                yield key, tuple(sorted(values))
    except Exception:
        return


def main():
    base = root()
    seen = defaultdict(list)
    seen_obj = defaultdict(list)

    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in SKIP and not d.startswith(".")]
        for fn in filenames:
            if not fn.endswith(EXT):
                continue
            p = os.path.join(dirpath, fn)
            try:
                text = open(p, errors="ignore").read()
            except Exception:
                continue
            for m in LIST_RE.finditer(text):
                members = tuple(sorted(
                    x.strip("'\"") for x in re.findall(r"['\"]([^'\"]+)['\"]", m.group(1))
                ))
                # CLI argument arrays are not guess lists about domain values.
                if any(x.startswith("-") for x in members):
                    continue
                if len(members) >= MIN_MEMBERS:
                    rel = os.path.relpath(p, base)
                    if rel not in seen[members]:
                        seen[members].append(rel)
            for key, members in object_array_fingerprints(text):
                rel = os.path.relpath(p, base)
                if rel not in seen_obj[(key, members)]:
                    seen_obj[(key, members)].append(rel)

    dupes = {k: v for k, v in seen.items() if len(v) > 1}
    dupes_obj = {k: v for k, v in seen_obj.items() if len(v) > 1}
    if not dupes and not dupes_obj:
        print("No duplicate constant lists found (S-05).")
        return 0

    print("DUPLICATE CONSTANT LISTS (S-05)\n")
    print("Two lists answering the same question will disagree, and the")
    print("disagreement shows up as a blank rather than a conflict.\n")

    def preview_of(members):
        return ", ".join(members[:4]) + ("..." if len(members) > 4 else "")

    combined = [(preview_of(members), files) for members, files in dupes.items()]
    combined += [(f"{key}: {preview_of(members)}", files) for (key, members), files in dupes_obj.items()]

    for preview, files in sorted(combined, key=lambda kv: -len(kv[1])):
        print(f"  [{preview}]")
        for f in files:
            print(f"      {f}")
        print()
    print("Fix: extract one dependency-free leaf both sides import. Never copy.")
    print("If the source can report these values live, delete the list entirely.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
