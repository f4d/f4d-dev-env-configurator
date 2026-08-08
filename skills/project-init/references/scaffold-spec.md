# Scaffold Spec

Exact layout and content rules. Templates live in `${CLAUDE_PLUGIN_ROOT}/templates/`.

## Target layout (NEW mode)

```
<project>/
├── CLAUDE.md                   # < 80 lines. Loads every turn.
├── README.md                   # human-facing. Different audience, different file.
├── .gitignore
├── .env.example
├── docker-compose.yml
├── scripts/dev-reset.sh
├── .github/workflows/verify.yml
└── .claude/
    ├── settings.json
    ├── rules/                  # selected modules only
    └── agents/                 # selected agents only
```

## CLAUDE.md assembly

From `templates/scaffold/CLAUDE.md.tmpl`. Fill every `{{TOKEN}}`. Leave no placeholder behind.

- `{{ARCH_MAP}}` — 3–8 lines. What the pieces are and how requests flow. No prose paragraphs.
- `{{RULES_INDEX}}` — one line per selected module: `` - `api.md` — HTTP surface, error envelope, versioning ``
- `{{INTEGRATIONS_TABLE}}` — from interview Q5: `| System | Direction | Metered | Adapter |`
- `{{CANONICAL_RULE}}` — from the reconciliation follow-up. If the user had no answer, write: `NOT YET DECIDED — do not build reconciliation logic until this is defined.`

**Hard limit: 80 lines.** If it exceeds that, move detail into a rules module. The file is a router, not a manual.

## Verify command by stack

| Stack | Verify |
|---|---|
| Python only | `uv run ruff check . && uv run mypy . && uv run pytest` |
| TS only | `pnpm typecheck && pnpm lint && pnpm test` |
| Both | chain them with `&&`, Python first |
| + contracts module | append `&& pnpm contracts:check` |
| + blockchain module | append `&& forge fmt --check && forge test && forge snapshot --check` |

Write it once, identically, in three places: `CLAUDE.md`, the `verify` script, and the CI workflow. If they can drift, they will.

## Toolchain pins

```bash
# Python
uv init --python 3.12
uv add --dev ruff mypy pytest hypothesis

# TypeScript
corepack enable && corepack use pnpm@latest

# Solidity (blockchain module only)
curl -L https://foundry.paradigm.xyz | bash && foundryup
```

Commit `.python-version`, `uv.lock`, `packageManager` in package.json, `pnpm-lock.yaml`, `foundry.toml`.

## Seed data requirements

A seed that only contains happy-path rows is worse than none — it teaches Claude the schema is simpler than it is. Every seed includes:

- A row with nulls in every nullable column
- A unicode name and an apostrophe in a text field
- A soft-deleted row, if soft delete exists
- Two rows from different sources describing the same real entity, if data-integration is enabled
- A record at the boundary of every constraint (max length, zero, negative where allowed)
- If storage: one small file, one at the size limit, one with a unicode filename

## Commit sequence

```bash
git init
git add -A
git commit -m "chore: project scaffold via f4d-kit"
```

One commit. Do not split the scaffold across several.

## RETROFIT specifics

- Write `CLAUDE.md.proposed`, never overwrite.
- Detect and adopt: package manager (lockfile present), indent style, existing test runner, existing lint config. The template yields to reality.
- Add `.claude/` even if nothing else changes — that alone is most of the value.
- Do not add docker-compose if the repo already has a working local setup. Document the existing one in CLAUDE.md instead.
