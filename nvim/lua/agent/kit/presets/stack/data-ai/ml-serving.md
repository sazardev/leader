<!-- name: ML model serving (FastAPI + ONNX Runtime) -->
<!-- desc: Python model serving: FastAPI, ONNX Runtime, micro-batching, a model registry in files, load tests -->

# STACK.md: ML model serving (FastAPI + ONNX Runtime)

## Summary

An inference service: models exported to ONNX are served by FastAPI with ONNX Runtime, requests are micro-batched for
throughput, and every model version is described by a manifest in a file-based registry (inputs, outputs, preprocessing,
checksum). Preprocessing and postprocessing are pure functions tested against reference outputs; load tests set the
latency and throughput budget.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Python 3.12 | Model tooling ecosystem |
| Packaging | uv | Reproducible environments |
| API | FastAPI + Pydantic v2 + uvicorn | Typed, async, OpenAPI |
| Inference | ONNX Runtime (CPU; CUDA execution provider when available) | Fast, framework-neutral |
| Arrays | NumPy | Pre/postprocessing |
| Batching | Own async micro-batcher (queue + max batch size + max wait) | Throughput without a heavy server |
| Registry | `models/<name>/<version>/` with `model.onnx` + `manifest.json` | Versioned, checksummed, reviewable |
| Metrics | Prometheus client (latency histograms, batch sizes, errors) | |
| Load tests | Locust or k6 | Latency/throughput budgets |
| Testing | pytest | |
| Lint/types | ruff + mypy `--strict` | |

## Project layout

```
pyproject.toml
models/
  sentiment/1.2.0/
    model.onnx                  stored with Git LFS or fetched by checksum, never edited
    manifest.json               inputs/outputs (names, dtypes, shapes), labels, preprocessing params, sha256
src/serving/
  main.py                       FastAPI app + composition root (loads the active versions)
  config.py                     which model versions are active, batch size, max wait, threads
  registry/
    manifest.py                 pydantic model of manifest.json
    loader.py                   verify checksum, create ort.InferenceSession with the right providers
  models/
    sentiment/
      preprocess.py             text → input tensors (pure)
      postprocess.py            output tensors → labels/scores (pure)
      predictor.py              Predictor: preprocess → batched run → postprocess
  batching/
    microbatcher.py             asyncio queue, batches up to N or T ms, resolves futures
  api/
    routes_predict.py           POST /v1/<model>/predict, GET /v1/models
    schemas.py
  observability/metrics.py
tests/
  models/sentiment/test_reference_outputs.py   known inputs → expected outputs (tolerance)
loadtests/locustfile.py
```

Dependency direction: `api → models (predictors) → registry, batching`; pre/postprocessing never import FastAPI.

## Conventions

- A model version is immutable: new weights = new version folder with its own manifest and checksum.
- The manifest is the contract: input names, dtypes and shapes are validated at load time and on every request.
- Pre/postprocessing are pure functions with reference tests; they never touch the session.
- One `InferenceSession` per model version, created at startup, shared; threads configured in config.
- The API exposes versioned routes and returns the model version used in every response.
- Health: `/healthz` (process) and `/readyz` (all active models loaded and warmed up with a dummy batch).

## Commands

| Task | Command |
| --- | --- |
| Install | `uv sync` |
| Run | `uv run uvicorn serving.main:app --workers 1` |
| Test | `uv run pytest` |
| Load test | `uv run locust -f loadtests/locustfile.py --headless -u 50 -r 10 -t 1m` |
| Lint / types | `uv run ruff check . && uv run mypy src` |

## Testing

- Reference tests: fixed inputs produce the recorded outputs within a tolerance, per model version.
- Unit tests for preprocessing edge cases (empty input, too long, unicode) and the micro-batcher (ordering, timeouts).
- API tests with `httpx.AsyncClient` against the app with a tiny test model.
- Load tests before changing batch size, threads or model version; results recorded with p50/p95/p99 and RPS.

## Quality gates

- ruff, mypy strict, pytest green; reference tests pass for every active model version.
- Load-test report attached when serving parameters or model versions change; p95 within the agreed budget.

## Dependencies

- Allowed: the table above.
- Do NOT use: the training framework (PyTorch/TensorFlow) at serving time when ONNX covers it, pickled models,
  models loaded from unverified URLs, global mutable state shared across requests outside the batcher.

## Rules for agents

- Never modify a model file or a shipped manifest; add a new version folder.
- Validate inputs against the manifest (names, dtypes, shapes) before running the session.
- Keep preprocessing and postprocessing pure and covered by reference tests.
- Create sessions once at startup; never per request.
- Route every inference through the micro-batcher; never call `session.run` from a route directly.
- Return the model name and version in every prediction response.
- Expose latency, batch size and error metrics for every model.
- Verify the checksum in the manifest before loading a model.
- Run the load test and record results when changing serving parameters.
