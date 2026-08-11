/**
 * Reference implementations of guard tests S-01 and S-02.
 *
 * Copy into the project's suite and point at real data. Written to FAIL first —
 * run against a known-bad case before trusting them (G-01).
 */
import { describe, expect, it } from "vitest";

// ─── S-01 — non-empty before assertion ──────────────────────────────────────
// An empty collection makes every assertion over it vacuously true.

export function assertNonEmpty<T>(collection: readonly T[], what: string): void {
  if (collection.length === 0) {
    throw new Error(
      `S-01: ${what} was empty. Every assertion over it would pass vacuously. ` +
        `Either the fixture is wrong or the code returned an empty collection ` +
        `where it should have thrown.`,
    );
  }
}

describe("S-01", () => {
  it("fails on an empty collection", () => {
    expect(() => assertNonEmpty([], "records")).toThrow(/S-01/);
  });
  it("passes on a real one", () => {
    expect(() => assertNonEmpty([1], "records")).not.toThrow();
  });
});

// ─── S-02 — no raw identifier in user-visible output ────────────────────────

const ID_PATTERNS: readonly RegExp[] = [
  /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i,
  /\b[0-9a-f]{24}\b/i,
  /\b(cus|sub|pi|ch|acct)_[A-Za-z0-9]{8,}\b/,
  /\bloc_[A-Za-z0-9]{8,}\b/,
];

export function assertNoRawIds(rendered: string, where = "output"): void {
  for (const pat of ID_PATTERNS) {
    const m = pat.exec(rendered);
    if (m) {
      throw new Error(
        `S-02: raw identifier "${m[0]}" reached ${where}. A hydration step ` +
          `returned the id instead of the value, and it rendered as if it were data.`,
      );
    }
  }
}

describe("S-02", () => {
  it("catches a raw uuid", () => {
    expect(() =>
      assertNoRawIds("Owner: 3f2504e0-4f89-11d3-9a0c-0305e82c3301", "profile"),
    ).toThrow(/S-02/);
  });
  it("allows a hydrated value", () => {
    expect(() => assertNoRawIds("Owner: Ian Lowell", "profile")).not.toThrow();
  });
});

// ---------------------------------------------------------------------------
// S-04 — a new value/type/shape must fail a check, never degrade to a default.
// The exhaustiveness pattern: every switch over a union ends in assertNever.
// When the union gains a member, COMPILATION fails at every unhandled switch —
// the new value cannot silently fall into a default arm.
export function assertNever(x: never, context = "value"): never {
  throw new Error(`Unhandled ${context}: ${JSON.stringify(x)} — a new union member reached a switch that does not handle it (S-04)`);
}
// Usage:
//   switch (kind) {
//     case "a": ...; break;
//     case "b": ...; break;
//     default: assertNever(kind, "RecordKind");
//   }
