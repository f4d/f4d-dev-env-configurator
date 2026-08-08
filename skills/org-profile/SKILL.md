---
name: org-profile
description: Create or update the company-level profile that every project in that company inherits — GitHub org, conventions, stack defaults, automation settings, business context, and constraints. Use when starting work for a company for the first time, when the user mentions a company or client not yet profiled, when org-level facts change (new GitHub org, new hosting, new client rules), or when the user asks to set up or review a company's defaults. /project-init calls this automatically when no profile exists.
---

# Org Profile

Company-level facts are asked **once per company**, not once per project. This skill owns them.

Profiles live at `~/.claude/f4d/orgs/<slug>.yml`. Template: `${CLAUDE_PLUGIN_ROOT}/templates/org/ORG.template.yml`.

## When to run

- `/project-init` finds no profile matching the company → it calls this first
- The user names a company you have no profile for
- An org-level fact changed — new GitHub org, hosting move, new client constraint
- Annually, as a review pass

## Check first

```bash
ls ~/.claude/f4d/orgs/
```

If a profile exists, **read it and confirm rather than re-interview.** Show the current values and ask what changed. Re-asking settled questions is the failure this skill exists to prevent.

## Interview — one round, grouped

Ask these together, not one at a time. Most have obvious defaults you should propose rather than ask open-ended.

**Identity**
1. Company name and short slug?
2. Is this your own business, client work, a joint venture, or personal?

**Code**
3. GitHub org?
4. Do this company's projects share one board and cadence, or stay siloed from each other?

**Conventions** — propose derived-from-slug defaults and let the user correct
5. Webhook header prefix, package scope, env var prefix — *"I'd use `X-F4D-Signature`, `@f4d`, and `F4D_`. Good?"*

**Stack defaults**
6. Default backend language, database, and hosting for new projects here?
7. Default object storage — **and note this is a default only; every project still confirms whether it needs storage at all**

**Automation**
8. Is the Claude GitHub App installed for this org? Subscription OAuth token or API key?
9. Auto PR review on every PR, off, or selective? Issue-to-PR via `@claude` on or off?
10. Any spend ceiling worth recording?

**Work tracking**
11. **Where does this company's work get tracked?** — `hub` (the central Work DB, default) | `hub+local` (mirrored to this company's workspace) | `local` (this company's workspace only)

    Propose `hub`. Only move off it when someone outside the hub workspace needs visibility, or contractual isolation demands it. Each alternative adds a sync target you own.

**Business**
12. This company's Notion workspace URL?
13. Do clients or outside stakeholders see status, and where do they look?

**Constraints** — the highest-value question in the interview
14. *"What makes work at this company different from your others? Anything live, anything a client owns, anything an agent must never touch?"*

Push on 14 if the answer is thin. This is where "the GHL instance is live," "the client owns the repo," and "everything must map to a billable item" come from — the facts that would otherwise be learned by breaking something.

## Write

Fill the template, leave nothing blank — use `none`, `n/a`, or `unknown` explicitly so a future read can tell "not applicable" from "never asked."

Save to `~/.claude/f4d/orgs/<slug>.yml`. Confirm the path. Never write credentials, tokens, or keys into a profile — record *which* auth mode is used, never the secret.

## How projects consume it

`/project-init` reads the profile and:
- Skips every question the profile already answers
- Proposes stack defaults instead of asking, so the user confirms rather than composes
- Applies conventions automatically — webhook prefix, scopes, env prefix
- Copies the `constraints` block into the project's `.claude/rules/org.md` verbatim, so every session in every repo of that company sees them
- Still asks the per-project questions: what this project does, its integrations, and whether it needs storage, money, blockchain, or frontend modules

**Nothing in a profile is a per-project answer.** If a fact varies between two projects in the same company, it belongs in the project interview, not here.
