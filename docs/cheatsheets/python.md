# Python

Filetype: `python`. Pack `python` (installer checklist, or `<leader>Sp` → Languages).

## Tools

| What | With |
|---|---|
| Types, navigation, hover | `basedpyright` (type checking "standard"; a `pyproject.toml`/`pyrightconfig.json` setting wins) |
| Lint, quick fixes, imports | `ruff` (its server; in light mode it runs as a linter instead) |
| Format on save | `ruff` (organize imports, then format) |
| Debug | `debugpy` (Mason; `Pk` repairs it) |
| Notebooks / REPL | JupyterLab, IPython (project dependencies, or the system ones) |
| Inlay hints | `basedpyright` (call-argument names and return types; on by default, `<leader>ph` toggles) |
| Auto-import | basedpyright code action (`<leader>ca`) and completion; local modules, the stdlib, and modules already imported |
| Treesitter | `python`, `toml`, `requirements` |

**Installed for you**: Python 3 is a system tool (the setup wizard offers it); `./install.sh` installs **uv** when the
Python pack is active (the pack now detects `python3`/`python`, so a machine with Python gets it); and **ruff**,
**basedpyright** and **debugpy** come from Mason. `Pk` (or `:PythonDoctor`) checks all of them and installs what is
missing. pandas, NumPy and JupyterLab are **not** global: they belong to each project's `.venv`.

**The project is the unit**: a uv project (one with `uv.lock`) runs through `uv run`; otherwise the `.venv` python;
otherwise `python3`. basedpyright uses the same `.venv` as its interpreter, so the imports you installed resolve.
`e` in the menu shows which interpreter is in use, `u` syncs it, and `t` prints the dependency tree.

## `<leader>p` menu (only in `*.py`)

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md). What they do:

- **Run**: the current file (a PEP 723 script with a `# /// script` header runs through `uv run`, so its inline
  dependencies work); the project's entry point; or the file as a module (`python -m …`, which keeps relative
  imports working). The file key saves the buffer first: the terminal runs what is on disk. The project entry point is
  detected, best first: `[project.scripts]` (run with `uv run`), a package with `__main__.py` (`src/<pkg>/` or
  `<pkg>/`), Django's `manage.py runserver`, and `main.py` / `app.py` / `run.py` when it is a FastAPI app
  (`uvicorn … --reload`), a Flask app (`flask … run --debug`), a Streamlit app, or a plain script. One candidate runs
  directly; several open a picker.

**Package vs file**: `uv init --app` writes `src/<pkg>/__init__.py` with a `main()` and a `[project.scripts]` entry.
`uv run <script>` (the project key) calls `main`; `python src/<pkg>/__init__.py` (the file key) only executes the file,
so it prints nothing unless it ends with `if __name__ == "__main__": main()`. `python -m <pkg>` (the module key) needs
a `<pkg>/__main__.py`; create it with:

```python
from . import main

main()
```

The script name is exactly the key in `[project.scripts]`: for `plot-xy = "plot_xy:main"` the command is
`uv run plot-xy`, not `uv run plot_xy`.
- **REPL**: plain `python -i <file>`, IPython with the file loaded, or JupyterLab in the project. IPython and JupyterLab
  have to be installed in the project (`uv add --dev ipython jupyterlab`) or on the machine.
- **Tests in the editor** (the same keys in every language with tests): the test under the cursor (a `test_…`
  function, a method of a `Test…` class, a whole `Test…` class), the file, the project, the last run again. pytest runs
  with a JUnit report: each test line gets a mark (✓ passed, ✗ failed, ○ skipped, … running), a failure is a
  diagnostic on the line of the test file where the traceback stops, the failures go to the quickfix list. Parametrized
  cases count as their function. From a module (not a test), the key runs its test file (`tests/test_<name>.py`). The
  file toggle jumps between a module and its test (creating `tests/test_<name>.py` when there is none). The output key
  shows what pytest printed.
- **Coverage**: `python -m pytest --cov` (needs `pytest-cov`).
- **ruff**: check the project, fix what it can, organize imports in the file, format the buffer (also on save).
- **basedpyright**: check the whole project from the command line (the LSP already reports diagnostics in the open
  files; this is the full check).
- **uv**: add packages, add dev packages, remove, sync, upgrade the lock, print the dependency tree, print what is
  outdated, and build the sdist/wheel into `dist/`.
- **Project** (the `P` submenu): create a new uv project (application, library, PEP 723 script or **data analysis**;
  applications and libraries are synced immediately, data analysis installs the full stack), create or recreate
  `.venv`, install and pin a Python version (`uv python install` + `uv python pin`), run any command inside the project
  environment (`uv run …`), run an ephemeral tool with `uvx`, open the project's files (`pyproject.toml`, `uv.lock`,
  `.python-version`, ruff/pytest config, Dockerfile, `.env`…), and **check/install the editor tools** (`Pk`).
- **Setup** (`<leader>pS`): ruff config (standard or strict), `pytest.ini`, `.python-version`, a uv Dockerfile and
  its `.dockerignore`, GitHub Actions (uv: lockfile install, ruff, pytest), pre-commit hooks, `.editorconfig`, a
  Makefile preset, `.gitignore`. Filled from `pyproject.toml` (name, `requires-python`); never overwrites.
- **Debug** (`<leader>pD`): the file, or the test under the cursor through pytest, with the project's interpreter;
  breakpoints, continue, steps and the panel, as for Dart.

## Workflows

**A new project, from nothing**

1. `<leader>pPi` (or `:PythonInit` from any buffer) → `Application`, and type the folder (e.g. `~/code/my-api`).
   `uv init` writes
   `pyproject.toml`, `src/<name>/`, `.python-version` and a console script; `uv sync` creates `.venv` and `uv.lock`.
2. `<leader>pa` / `<leader>pd` to add runtime or dev dependencies (uv updates the lock and the venv).
3. `<leader>pp` runs the console script; `<leader>pr` runs a single file; `<leader>pl` runs it as a module.
4. `<leader>pm` tests the test under the cursor; `<leader>pDd` debugs the file.

**A data-analysis project (the pandas book)**

1. `<leader>pPi` (or `:PythonInit`) → `Data analysis` and type the folder. `uv init --bare` + `uv add` installs
   pandas 2.x (the 2022 book's era), NumPy, matplotlib, SciPy, statsmodels, scikit-learn, pyarrow, JupyterLab,
   IPython, the Excel/HTML/SQL/HDF5 readers and `pytest`/`pytest-cov`/`ruff`; `.venv` and `uv.lock` are created.
2. `<leader>pj` opens JupyterLab in the project and `<leader>pI` IPython with the current file. `<leader>pp` falls back
   to the current file (a bare project has no console script); use a notebook or `<leader>pPr` for a command.
3. `<leader>pa` adds more packages (e.g. `seaborn polars duckdb`); `<leader>pd` adds dev tools.
4. `<leader>pu` re-syncs after pulling; `<leader>pPk` repairs the editor tools if anything is missing.

**An existing project**

1. `<leader>pPk` (check/install the editor tools), `<leader>pu` (`uv sync`) and `<leader>pe` (which interpreter is in
   use).
2. `<leader>pv` / `<leader>px` (ruff), `<leader>py` (basedpyright), `<leader>pf` (format).
3. `<leader>pt` (dependency tree), `<leader>pPo` (outdated), `<leader>pb` (build).
4. `<leader>pPr` runs an arbitrary command in the project environment (e.g. `pytest -k api -x`); `<leader>pPx` runs a
   one-off tool without adding it to the project (`uvx ruff check .`).

**Data analysis**

`<leader>pj` starts JupyterLab from the project; `<leader>pI` opens IPython with the current file loaded. Add them to
the project with `<leader>pd` (`ipython jupyterlab`) so they see the project's pandas/NumPy.

## Snippets

`testfunction`, `parametrize`, `fixture`, `dataclass` (frozen, slots), `ifmain`, `exception` (with its data).

## Pitfalls

- basedpyright needs the dependencies installed in the `.venv` to resolve imports: `uv sync` first.
- `uv add` / `uv sync` need a `pyproject.toml`; the menu says so instead of creating one by accident. Use the `P`
  submenu to create a project.
- `Pv` recreating `.venv` deletes the packages installed in it; the modal warns first.
- `Pp` may download a Python version; `uv python pin` only writes `.python-version`.
- `r` is "run file", not "run project": a package `__init__.py` that only defines `main()` prints nothing; use the
  project key (`uv run <script>`) or add the `if __name__ == "__main__": main()` guard. `l` needs `<pkg>/__main__.py`.
- `Pr` (`uv run …`) is for commands, not for shell syntax: what you type goes after `uv run` as-is.
- Tests from a class that does not start with `Test` are not collected by pytest, so they get no mark either.
- No global data stack: pandas/NumPy/JupyterLab live in each project's `.venv`, so `Pi` → `Data analysis` (or
  `uv add`) is what makes them available; the system Python stays clean.
- Tests and coverage need `pytest` and `pytest-cov` in the project: `<leader>pd` adds them
  (`uv add --dev pytest pytest-cov`); the data starter includes them.
- The data starter pins `pandas<3` to match the 2022 book. `uv add 'pandas>=3'` upgrades to pandas 3 (then check the
  migration notes: Copy-on-Write and the `str` dtype change some idioms; chained assignment stops working).
- `Pk` installs `uv` and the Mason tools when they are missing; `:MasonInstall debugpy` is the manual fallback.
