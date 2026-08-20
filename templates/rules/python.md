---
id: python
always_apply: false
---
# Python

- Run everything through `uv`: `uv run pytest`, `uv run ruff check .`, `uv run mypy .`. Never bare `python` or `pip`.
- Python 3.12+. Pinned in `.python-version`, locked in `uv.lock`.
- `mypy` in strict mode. No `# type: ignore` without a same-line reason comment.
- `ruff` for lint and format. No competing formatter.
- Never `except:` or `except Exception:` without re-raising or logging with context.
- Pydantic v2 for every external boundary — HTTP in, HTTP out, queue messages, config.
- `Decimal` for money and anything summed for a human. `float` is for physics, not invoices.
- Prefer explicit dataclasses/models over dicts passed between layers.
- Tests: `pytest`. Property tests via `hypothesis` for parsers, normalizers, and any pure calculation.
