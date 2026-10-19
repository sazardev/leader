<!-- name: PostgreSQL full-text search -->
<!-- desc: search inside Postgres with tsvector, GIN indexes and ranking; no extra service to run -->
<!-- for: server backend fullstack selfhosted !mobile -->

## Stack

| Search | PostgreSQL full-text search (`tsvector` generated column, GIN index, `websearch_to_tsquery`, `ts_rank`) | No second system to run or keep in sync; transactional with the data |

## Project layout

```
migrations/                    generated tsvector column + GIN index per searchable table
src/search/                    query builders (websearch_to_tsquery, ts_rank, ts_headline) per entity
```

## Conventions

- The search column is a `GENERATED ALWAYS AS (...) STORED` `tsvector` built with `setweight` (title `A`, body `B`), never computed per query.
- Every `tsvector` column has a `GIN` index; check with `EXPLAIN ANALYZE` that it is used.
- User input goes through `websearch_to_tsquery('<config>', $1)` as a bound parameter; the text search configuration (`english`, `simple`) is explicit and the same at index and query time.
- Results are ordered by `ts_rank` (or `ts_rank_cd`) then by a stable tie-breaker; use `ts_headline` only on the page of results shown.
- For typo tolerance add `pg_trgm` with a trigram GIN index as a second pass; do not replace the full-text index with it.

## Commands

| Query plan | `psql "$DATABASE_URL" -c "EXPLAIN ANALYZE <search query>"` |

## Testing

- Tests run against a real PostgreSQL with seeded rows and assert ranking order, stemming and empty-query behaviour.

## Rules for agents

- Never build a `tsquery` by concatenating user input into SQL; always bind parameters.
- Never use `ILIKE '%term%'` for search on large tables.
- Add the GIN index in the same migration as the column.
