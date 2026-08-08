# Interview Guide

## Reading ambiguous answers

| User says | Probably means | Follow up with |
|---|---|---|
| "it pulls data from a few APIs" | data-integration module, adapters, fixtures | "Which ones, and are any of them metered or paid?" |
| "it handles files" | storage module — but not necessarily determinism | "Who uploads them, how big, and does anyone else fetch them by URL?" |
| "there's a dashboard" | frontend module may apply | "Is it internal-only, or does anyone outside the company see it?" |
| "it does some calculations" | possible money module | "Do any of those numbers turn into an invoice, payout, or price?" |
| "it's kind of live already" | livesystem module, RETROFIT mode | "What's the blast radius if something in there breaks right now?" |
| "just a simple CRUD app" | still needs core + api + database | "What happens when two of those integrations disagree about the same record?" |

## Questions worth asking that users rarely volunteer

- **"What's the canonical record, and which source wins in a conflict?"** — For multi-source projects this is the single most important design decision, and it is almost never in the initial description. If there is no answer, that is the first thing to design.
- **"What has to be idempotent?"** — Anything with retries, webhooks, or payments. If the answer is "nothing," probe once more.
- **"What would you be embarrassed to leak in a log?"** — Faster and more honest than asking about PII directly.
- **"What did you have to explain to Claude twice last week?"** — In RETROFIT mode, the highest-yield question in the whole interview. The answer becomes a rule.

## Interview anti-patterns

- Do not ask about hosting, CI provider, or linter preferences. Infer from what exists, or use the defaults in `scaffold-spec.md`.
- Do not ask "do you want tests?" Assume yes; ask what the hard-to-test part is.
- Do not ask more than four questions in one message.
- Do not proceed on silence. If a Round 3 answer is missing, leave the module out — a missing rule is recoverable, a wrong rule is corrosive.

## When to stop interviewing

Stop when you can fill in every line of the Step 2 plan table without guessing. If you are guessing at one line, ask about that one line only.
