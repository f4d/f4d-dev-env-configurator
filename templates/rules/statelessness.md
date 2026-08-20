---
id: statelessness
always_apply: false
---
# Statelessness

The premise: **any instance can serve any request, and any instance can die at any
moment without losing anything that mattered.**

This failure class is structurally invisible. Local dev runs one instance, tests
run one instance, CI runs one instance — and the first multi-instance environment
is production. Statefulness bugs therefore present as intermittent flakiness
rather than as defects, and survive review because the code is correct in
isolation.

## The contract

- No request handler may depend on having seen a previous request.
- Any instance may be killed between any two requests. Nothing that mattered is lost.
- Restarting the process loses **nothing** except performance.

## Where state must live

| State | Never | Always |
|---|---|---|
| Session / auth | Server memory | Signed token, or a shared session store |
| Cache | Module-level dict | Redis, or accept per-instance and make it provably safe to diverge |
| Rate limits | In-process counter | Shared store. N instances otherwise means N× the limit. |
| Locks | `threading.Lock`, in-process mutex | Advisory DB lock or a distributed lock with a TTL |
| Uploads in progress | Local disk | Object storage, direct via presigned URL |
| Temp/derived files | Local disk between requests | Object storage, or within one request only |
| Background jobs | A thread in the web process | A queue with a durable backend |
| Schedules / cron | In-process scheduler | External scheduler, or leader election. N instances otherwise fire N times. |
| Long-operation progress | Memory | A row, keyed and readable by any instance |
| WebSocket / SSE state | Instance-local only | A shared pub/sub, or accept and handle reconnect-to-a-different-instance |

## Rules

- **Module-level mutable state is a defect** unless it is provably immutable after
  import. A dict that gets written to at runtime is per-instance state pretending
  to be a cache.
- **Migrations never run at boot.** Instances race; one wins and the rest crash or,
  worse, half-apply. Migrations run as a separate step in the deploy.
- **Every write path is idempotent** or carries an idempotency key. A retry, a
  duplicate webhook, or a request that landed on a second instance must not
  double-apply.
- **Sticky sessions are a workaround, not a design.** If the system requires them,
  say so explicitly and name what would be needed to remove them.
- **Readiness is not liveness.** `/readyz` reports whether dependencies are
  reachable from *this* instance. `/healthz` reports the process is alive. A load
  balancer needs both to mean different things.
- **Graceful shutdown is required.** On SIGTERM: stop accepting, finish in-flight,
  release locks, exit. An instance that dies mid-request must not leave a lock held.
- **Nothing on the local filesystem outlives a request.** Assume the disk is
  ephemeral, because on Render, Fly, Cloud Run, and every serverless target, it is.
- **A cache miss must be correct, never just slower.** If behavior differs on a cold
  instance, the cache is load-bearing state.

## Prove it, do not assume it

- **Local dev runs two instances.** This is the whole game. One instance makes every
  statefulness bug invisible until production.
- At least one integration test exercises a flow across two instances: write on A,
  read on B.
- A restart test: kill the process mid-flow, confirm nothing was lost.
- If any of the above is impractical, **name what would catch the problem instead**.
  Silence reads as "stateless."

## Import-time registries (the sanctioned ST-01 exception)

First live test of the kit (GHL-MCP, 2026-08-10) hit this false positive, so it
is now doctrine:

A module-level mutable collection whose **only** mutations are module-top-level
registration calls — the pattern

```ts
const registry: Record<string, Component> = {};            // stateless-ok import-time registration — populated only by top-level registerX() calls below/in importers
export function registerX(key, c) { registry[key] = c; }   // called ONLY at module top level
```

is **static after load**: every instance evaluates the same modules and ends
with an identical registry. No cross-instance drift is possible. Annotate the
declaration `stateless-ok import-time registration — <who registers>`.

The boundary, and it is sharp: the moment any handler, request path, or
runtime event calls the register function, this is real ST-01 — the scanner
cannot see call-site timing across files, so **the annotation is a claim a
reviewer verifies**, exactly like every other `stateless-ok`. The claim has TWO
halves and the reason must cite both: (1) every register call site is module
top level, and (2) every registering module is **eagerly and unconditionally
imported at startup on every instance** — a registration module that is lazy-
or dynamically imported from a request handler is still "top level"
syntactically, but only the instance that served the request populates its
registry, which is exactly the drift this gate exists to prevent.

**Who does this work — and it is not the user.** The agent writing the
annotation runs both checks in-session (a grep and an import-path trace,
seconds of work) and pastes the evidence into the reason. `/project-audit`
re-runs the call-site grep on every audit and flags any annotation whose
evidence no longer holds. The human's role is the decision when a discrepancy
surfaces — never the legwork. An annotation protocol that assumes a person
runs terminal commands is a protocol that stops being followed.
