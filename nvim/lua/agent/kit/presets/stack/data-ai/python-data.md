<!-- name: Python data pipelines (Polars + DuckDB) -->
<!-- desc: typed data pipelines: Python 3.12, uv, Polars, DuckDB, pydantic contracts, pytest, ruff -->

# STACK.md: Python data pipelines (Polars + DuckDB)

## Summary

Batch data pipelines written as small, typed, pure functions: each step takes a DataFrame (or a DuckDB relation) and
returns a new one. Polars does the transformations, DuckDB does SQL over files (Parquet, CSV) and is the local warehouse,
pydantic validates everything that enters or leaves (configs, row contracts, API payloads). IO lives at the edges; the
transformation core is testable without files or network.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Python 3.12 | Typed, mature data ecosystem |
| Packaging | uv (`pyproject.toml`, `uv.lock`) | Fast, reproducible environments, one tool |
| DataFrames | Polars (lazy API) | Fast, columnar, explicit expressions, no index surprises |
| SQL engine | DuckDB | In-process SQL over Parquet/CSV, zero ops |
| Contracts | pydantic v2 | Validated configs and row schemas at the boundaries |
| Storage format | Parquet | Typed, compressed, columnar |
| CLI | Typer | One command per pipeline |
| Logging | `structlog` (JSON) | Row counts and timings per step |
| Testing | pytest + `polars.testing.assert_frame_equal` + hypothesis (optional) | Pure steps tested with tiny frames |
| Lint/format | ruff (lint + format) | One fast tool |
| Types | mypy `--strict` (or pyright strict) | Catch schema/type drift |

## Project layout

```
pyproject.toml
src/pipelines/
  config.py                  pydantic Settings: paths, dates, thresholds (from env/CLI)
  contracts/
    orders.py                pydantic row model + Polars schema of the orders dataset
  steps/                     pure transformations: DataFrame/LazyFrame in, out — no IO
    clean_orders.py          one step per file
    enrich_customers.py
    aggregate_daily.py
  io/                        the edges: read and write
    read_sources.py          CSV/Parquet/HTTP → LazyFrame (validated against contracts)
    write_outputs.py         LazyFrame → Parquet / DuckDB tables
  sql/
    daily_report.sql         DuckDB queries kept as files, loaded by name
  flows/
    daily.py                 composes io + steps for one pipeline (the only place that knows the order)
  cli.py                     Typer app: `pipelines daily --date 2026-10-16`
tests/
  steps/test_clean_orders.py tiny in-memory frames, exact expected output
  flows/test_daily.py        end to end on fixture files in tests/data/
  data/                      small fixture CSV/Parquet files
```

Dependency direction: `cli → flows → (io, steps) → contracts`. `steps/` never imports `io/`; nothing imports `cli`.

## Conventions

- A step is a pure function `def clean_orders(orders: pl.LazyFrame) -> pl.LazyFrame`, one per file, named by what it does.
- Stay lazy (`scan_parquet`, `LazyFrame`) until the write; `collect()` only in `io/` or tests.
- Every dataset has a contract in `contracts/` (pydantic model + Polars schema); reads validate, writes cast to it.
- Column names are `snake_case`; no positional column access; no `apply`/`map_elements` where an expression exists.
- SQL lives in `sql/*.sql`, never in Python strings longer than one line; parameters bound, never formatted in.
- Config comes from `config.py` (env + CLI flags); no hardcoded paths or dates.
- Each flow logs rows in/out and time per step; a step that drops more rows than its threshold fails the run.

## Commands

| Task | Command |
| --- | --- |
| Install | `uv sync` |
| Run a pipeline | `uv run pipelines daily --date 2026-10-16` |
| Test | `uv run pytest` |
| Lint | `uv run ruff check .` |
| Format | `uv run ruff format .` |
| Types | `uv run mypy src` |
| SQL shell | `uv run duckdb data/warehouse.duckdb` |

## Testing

- Steps: unit tests with 3–10 row frames built in the test; assert with `assert_frame_equal` (order and dtypes checked).
- Contracts: a test per contract that a valid and an invalid row behave as expected.
- Flows: one end-to-end test per flow on fixture files in `tests/data/`, writing to a `tmp_path`.
- Property tests (hypothesis) for steps with arithmetic or date logic (sums preserved, no row duplication).

## Quality gates

- `ruff check` and `ruff format --check` clean; `mypy --strict` clean on `src/`.
- `pytest` green; every new step comes with its test.
- No file in `steps/` imports from `io/`, `os`, `pathlib` or network libraries (checked in review).

## Dependencies

- Allowed: the table above. A new library needs a reason (what Polars/DuckDB cannot do).
- Do NOT use: pandas for new code (Polars covers it; convert at the edge only if a library demands pandas), notebooks as
  production code (they explore; pipelines live in `src/`), ORMs for analytics, Spark for data that fits on one machine.

## Rules for agents

- Write transformations as pure functions over `LazyFrame` in `steps/`, one per file; never read or write files there.
- Use Polars expressions (`pl.col`, `with_columns`, `group_by().agg`), never row loops or `map_elements` when an expression exists.
- Validate every input against its contract when it is read; cast outputs to the contract schema before writing.
- Keep SQL in `sql/` files with bound parameters; never build SQL with f-strings.
- Never call `collect()` inside a step; collect once at the write or in tests.
- Add or update the contract when a column is added, renamed or retyped, in the same change.
- Every new step gets a test with a tiny hand-written frame and an exact expected frame.
- Log row counts in and out per step in flows; fail loudly when a threshold is crossed.
- Never commit data files bigger than a test fixture; real data stays out of git.
