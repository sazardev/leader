# Python

Filetype: `python`. Pack `python` (installer checklist, or `<leader>Sp` → Languages).

## Tools

| What | With |
|---|---|
| Types, navigation, hover | `basedpyright` (type checking "standard"; a `pyproject.toml`/`pyrightconfig.json` setting wins) |
| Lint, quick fixes, imports | `ruff` (its server; in light mode it runs as a linter instead) |
| Format on save | `ruff` (organize imports, then format) |
| Debug | `debugpy` (Mason) |
| Treesitter | `python`, `toml`, `requirements` |

**The project's interpreter is used everywhere**: a `.venv/` or `venv/` at the root (uv, `python -m venv`, poetry with
in-project venvs) is basedpyright's interpreter, so the imports you installed resolve. A uv project (one with `uv.lock`)
runs through `uv run`; otherwise the `.venv` python; otherwise `python3`. `e` in the menu shows which one is in use.

## `<leader>p` menu (only in `*.py`)

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md). What they do:

- **Run**: the file, or a REPL with it loaded.
- **Tests in the editor** (the same keys in every language with tests): the test under the cursor (a `test_…`
  function, a method of a `Test…` class, a whole `Test…` class), the file, the project, the last run again. pytest runs
  with a JUnit report: each test line gets a mark (✓ passed, ✗ failed, ○ skipped, … running), a failure is a
  diagnostic on the line of the test file where the traceback stops, the failures go to the quickfix list. Parametrized
  cases count as their function. From a module (not a test), the key runs its test file (`tests/test_<name>.py`). The
  file toggle jumps between a module and its test (creating `tests/test_<name>.py` when there is none). The output key
  shows what pytest printed.
- **Coverage**: `pytest --cov` (needs `pytest-cov`).
- **uv**: add packages (`--dev pytest` works: what you type goes after `uv add`), remove, sync, upgrade the lock.
- **ruff**: check the project, fix what it can, organize imports in the file.
- **Debug** (`<leader>pD`): the file, or the test under the cursor through pytest, with the project's interpreter;
  breakpoints, continue, steps and the panel, as for Dart.
- **Setup** (`<leader>pS`): ruff config (standard or strict), `pytest.ini`, `.python-version`, a uv Dockerfile and
  its `.dockerignore`, GitHub Actions (uv: lockfile install, ruff, pytest), pre-commit hooks, `.editorconfig`, a
  Makefile preset, `.gitignore`. Filled from `pyproject.toml` (name, `requires-python`); never overwrites.

## Snippets

`testfunction`, `parametrize`, `fixture`, `dataclass` (frozen, slots), `ifmain`, `exception` (with its data).

## Pitfalls

- basedpyright needs the dependencies installed in the `.venv` to resolve imports: `uv sync` first.
- Tests from a class that does not start with `Test` are not collected by pytest, so they get no mark either.
