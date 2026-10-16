<!-- name: LLM app with RAG (FastAPI + pgvector) -->
<!-- desc: Python FastAPI LLM app: retrieval with pgvector, versioned prompts, eval harness, cost/latency logs -->

# STACK.md: LLM app with RAG (FastAPI + pgvector)

## Summary

An API that answers questions over your own documents: ingestion chunks and embeds documents into Postgres with pgvector,
retrieval finds the relevant chunks, the LLM answers with citations. Prompts are versioned files, every call logs tokens,
cost and latency, and an evaluation harness scores retrieval and answers on a fixed dataset before any prompt or model
change ships. Hexagonal: the LLM provider, the embedder and the vector store are ports.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Python 3.12 | Best LLM/ML library support |
| Packaging | uv | Reproducible, fast |
| API | FastAPI + Pydantic v2 | Typed requests/responses, streaming responses (SSE) |
| Vector store | PostgreSQL 16 + pgvector (HNSW index) | One database for documents, chunks, vectors and logs |
| DB access | SQLAlchemy 2 (async) + Alembic | Explicit queries, migrations |
| LLM client | Official provider SDK (e.g. `anthropic`) behind an `LLM` port | Swap models/providers without touching use cases |
| Embeddings | Provider embeddings or `sentence-transformers` behind an `Embedder` port | Same reason |
| Chunking | Own small module (by headings/paragraphs, token-sized) | Predictable, testable |
| Evals | pytest-based harness + a JSONL golden set | Regressions caught before shipping |
| Observability | structlog JSON + OpenTelemetry spans per LLM/retrieval call | Cost, latency, tokens per request |
| Lint/types | ruff + mypy `--strict` | |

## Project layout

```
pyproject.toml
src/app/
  main.py                      FastAPI app + composition root (wires adapters into use cases)
  config.py                    pydantic Settings (model names, top_k, limits, keys from env)
  domain/
    chunk.py                   Chunk, Citation value objects
    answer.py                  Answer with citations and usage
    ports.py                   LLM, Embedder, VectorStore, DocumentStore protocols
  use_cases/
    ingest_document.py         split → embed → store (idempotent by content hash)
    answer_question.py         retrieve → build prompt → call LLM → parse citations
  retrieval/
    chunker.py                 text → chunks with overlap, token-bounded
    rerank.py                  optional reranking of candidates
  prompts/
    answer.v3.md               versioned prompt templates (the version is in the file name)
    loader.py                  loads a prompt by name+version, fills variables
  adapters/
    llm_anthropic.py           implements LLM; returns text + usage (tokens, cost)
    embedder_provider.py       implements Embedder
    pgvector_store.py          implements VectorStore (HNSW cosine search)
  api/
    routes_ask.py              POST /ask (streams), POST /documents
    schemas.py                 request/response models
  telemetry/
    usage_log.py               one row per LLM call: model, prompt version, tokens, cost, latency
migrations/
evals/
  golden.jsonl                 question, expected sources, reference answer
  run_evals.py                 retrieval recall@k, answer faithfulness, cost per question
tests/
```

Dependency direction: `api → use_cases → domain`; `adapters` implement `domain/ports.py`; `main.py` wires them.

## Conventions

- Prompts are files in `prompts/` named `<name>.v<N>.md`; changing a prompt means a new version, never editing a shipped one.
- Every LLM and embedding call goes through a port and records model, prompt version, tokens in/out, cost and latency.
- Retrieval parameters (`top_k`, similarity threshold, chunk size) live in config and are part of the eval report.
- Answers carry citations (chunk ids) and the API returns them; an answer without sources says so.
- Ingestion is idempotent: a document is keyed by its content hash; re-ingesting does nothing.
- Timeouts and retries with backoff on every provider call; a budget per request caps tokens.

## Commands

| Task | Command |
| --- | --- |
| Install | `uv sync` |
| Run | `uv run fastapi dev src/app/main.py` |
| Migrate | `uv run alembic upgrade head` |
| Ingest | `uv run python -m app.cli ingest docs/` |
| Test | `uv run pytest` |
| Evals | `uv run python evals/run_evals.py --report evals/report.md` |
| Lint / types | `uv run ruff check . && uv run mypy src` |

## Testing

- Unit: chunker, prompt loader, citation parsing, use cases with fake ports (deterministic fake LLM and embedder).
- Integration: pgvector store against a real Postgres (testcontainers) with a handful of vectors.
- Evals: the golden set runs on every prompt/model/retrieval change; the report compares recall@k, faithfulness and cost
  with the previous run and a drop beyond the agreed threshold blocks the change.
- No test calls a real provider; evals are the only place that does, explicitly.

## Quality gates

- ruff, mypy strict and pytest green.
- Eval report committed with any change to prompts, models, chunking or retrieval parameters.
- Cost per question in the eval report does not grow without a note explaining why.

## Dependencies

- Allowed: the table above; the provider SDK of the chosen model.
- Do NOT use: heavy orchestration frameworks (LangChain-style chains) for what three functions do; a separate vector
  database while pgvector is enough; prompts inlined in Python code; unversioned prompt edits.

## Rules for agents

- Never call a model or embedder directly from a route or use case: go through the ports in `domain/ports.py`.
- Never edit a shipped prompt file; add `name.v<N+1>.md` and switch the version in config.
- Log tokens, cost, latency, model and prompt version for every LLM call through `telemetry/usage_log.py`.
- Every answer returns its citations; never let the model answer without retrieved context unless the route says so.
- Keep retrieval parameters in config; changing them requires running the evals and committing the report.
- Tests use fake LLM/embedder adapters; never hit a paid API in unit or integration tests.
- Bound every request: max retrieved chunks, max output tokens, timeout, and a per-request budget.
- Strip or escape user input that ends up in prompts; never put secrets in prompts or logs.
- Ingestion must be idempotent by content hash; never duplicate chunks.
