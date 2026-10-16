<!-- name: Python CLI (Typer + Rich) -->
<!-- desc: Python command-line tool: Typer commands, Rich output, uv project, pytest, ruff, mypy, uv build -->

# STACK.md: Python CLI (Typer + Rich)

## Summary

A command-line tool in Python: Typer turns typed functions into commands with help and completion, Rich renders tables,
progress and errors. The core is plain Python with no CLI imports, so it is testable and reusable; commands are thin
adapters that parse arguments, call the core and print. Managed end to end with uv.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Python 3.12+ | Mature, type hints |
| CLI | Typer | Commands from typed functions, completion |
| Output | Rich | Tables, progress, readable errors |
| Config | TOML in the user config dir (`platformdirs`) + env overrides | Per-OS paths |
| Project | uv (`pyproject.toml`, `uv.lock`) | Fast, one tool |
| Testing | pytest + `typer.testing.CliRunner` | Commands tested like a user |
| Lint | ruff (lint + format) | One fast tool |
| Types | mypy `--strict` | Contracts checked |
| Package | `uv build` → wheel; `uv tool install` / pipx | Installable command |

## Project layout

```
pyproject.toml                [project.scripts] tool = "tool.cli:app"
src/tool/
  cli.py                      Typer app, registers command modules
  commands/
    sync.py                   one command (or sub-app) per file
    status.py
  core/
    sync.py                   the logic, no Typer/Rich imports
    models.py                 dataclasses
    errors.py
  output.py                   Rich console and renderers
  config.py
tests/
  core/test_sync.py
  commands/test_sync_cmd.py
```

Dependency direction: `commands → core`; `core` never imports `typer` or `rich`.

## Conventions

- Commands print through `output.py`; exit codes: 0 ok, 1 user error, 2 usage error.
- Errors from the core are domain exceptions; commands catch them and print one readable line (no traceback unless `--debug`).
- Output that other tools read gets a `--json` flag.

## Commands

| Task | Command |
| --- | --- |
| Install | `uv sync` |
| Run | `uv run tool --help` |
| Test | `uv run pytest` |
| Lint | `uv run ruff check .` |
| Format | `uv run ruff format .` |
| Types | `uv run mypy src` |
| Build | `uv build` |

## Testing

- Core functions unit-tested; each command tested with `CliRunner` for output and exit code; file system work in `tmp_path`.

## Quality gates

- ruff (lint and format check), mypy strict and pytest clean; `uv build` produces an installable wheel.

## Dependencies

- Typer, Rich, platformdirs; anything else needs a reason.
- Do NOT use: argparse boilerplate next to Typer, `print` for output, global mutable state.

## Rules for agents

- Keep `typer`/`rich` imports out of `core/`.
- One command per file in `commands/`; register it in `cli.py`.
- Type every function; keep mypy strict green.
- Return exit codes explicitly with `typer.Exit(code)`.
- Add `--json` output for anything scriptable.
- Never write outside the user's config/data dirs or paths they pass.
- Test commands through `CliRunner`, not by calling functions directly.
- Add dependencies with `uv add`, never by editing the lockfile.
