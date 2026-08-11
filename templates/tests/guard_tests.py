"""
Reference implementations of guard tests S-01 and S-02.

Copy into the project's test suite and point them at real data. They are written
to FAIL first — run them against a known-bad case before trusting them (G-01).
"""
import re

import pytest

# ─── S-01 — non-empty before assertion ────────────────────────────────────────
# An empty collection makes every assertion over it vacuously true. This is the
# single highest-yield guard against a passing-but-meaningless suite.


def assert_nonempty(collection, what: str):
    """Use in place of a bare loop. Never iterate without this first."""
    assert len(collection) > 0, (
        f"S-01: {what} was empty. Every assertion over it would pass vacuously. "
        f"Either the fixture is wrong or the code returned an empty collection "
        f"where it should have raised."
    )


def test_s01_catches_vacuous_pass():
    """The guard itself, proved: it must fail on an empty collection."""
    with pytest.raises(AssertionError, match="S-01"):
        assert_nonempty([], "records")
    assert_nonempty([1], "records")  # and pass on a real one


# ─── S-02 — no raw identifier in user-visible output ──────────────────────────
# A raw id reaching the UI means a hydration step silently no-opped.

ID_PATTERNS = [
    re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", re.I),  # uuid
    re.compile(r"\b[0-9a-f]{24}\b", re.I),          # mongo objectid
    re.compile(r"\b(cus|sub|pi|ch|acct)_[A-Za-z0-9]{8,}\b"),  # stripe-style
    re.compile(r"\bloc_[A-Za-z0-9]{8,}\b"),          # ghl-style location id
]


def assert_no_raw_ids(rendered: str, where: str = "output"):
    for pat in ID_PATTERNS:
        m = pat.search(rendered)
        assert not m, (
            f"S-02: raw identifier {m.group(0)!r} reached {where}. "
            f"A hydration step returned the id instead of the value, and it "
            f"rendered as if it were data."
        )


def test_s02_catches_raw_id():
    bad = "Owner: 3f2504e0-4f89-11d3-9a0c-0305e82c3301"
    with pytest.raises(AssertionError, match="S-02"):
        assert_no_raw_ids(bad, "profile page")
    assert_no_raw_ids("Owner: Ian Lowell", "profile page")


# ---------------------------------------------------------------------------
# S-04 — a new value/type/shape must fail a check, never degrade to a default.
# Python's runtime twin of assertNever: call it in the else of every
# enum/literal dispatch. New member -> loud failure at the boundary, never a
# silent default. (On 3.11+, typing.assert_never gives the static half too.)
def assert_never(value, context="value"):
    raise AssertionError(
        f"Unhandled {context}: {value!r} — a new value reached a dispatch that does not handle it (S-04)"
    )
