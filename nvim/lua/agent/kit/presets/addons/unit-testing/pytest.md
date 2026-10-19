<!-- name: pytest -->
<!-- desc: Python tests with pytest: fixtures, parametrization, markers, coverage and strict config -->
<!-- for: python -->

## Stack

| Unit tests | pytest (`pyproject.toml` `[tool.pytest.ini_options]`, fixtures in `conftest.py`, `pytest-cov`) | Plain asserts, powerful fixtures and parametrization |

## Project layout

```
tests/                         mirrors the package layout (tests/orders/test_pricing.py)
tests/conftest.py              shared fixtures: app/client, temp database, factories
pyproject.toml                 testpaths, addopts = "--strict-markers --strict-config -ra", markers, coverage
```

## Conventions

- Test files `test_*.py`, functions `test_<behaviour>`; plain `assert`, no `unittest.TestCase` for new code.
- Use fixtures for setup and teardown (`yield`), scoped as narrow as possible; shared ones live in `conftest.py`.
- Many inputs, one test: `@pytest.mark.parametrize` with readable `ids=`.
- Fake time and the network (`freezegun` or `time-machine`, `respx` / `responses`); use `tmp_path` and `monkeypatch`, never real paths or global state.
- Markers (`slow`, `integration`) are declared in the config; slow and integration tests are selectable with `-m`.
- Coverage is measured with `--cov=<package> --cov-fail-under=<n>` in CI.

## Commands

| Test | `pytest` |
| Test fast | `pytest -x -q -m "not slow"` |
| Coverage | `pytest --cov=<package> --cov-report=term-missing` |

## Quality gates

- `pytest --cov=<package> --cov-fail-under=<n>` passes.

## Rules for agents

- Every bug fix and new function gets a test that fails without the change.
- Never mark a failing test `skip`/`xfail` to get a green run; fix the cause.
- Never share mutable state between tests or depend on test order.
