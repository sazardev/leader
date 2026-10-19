<!-- name: Typesense -->
<!-- desc: typo-tolerant in-memory search engine with typed collections, facets and scoped API keys -->
<!-- for: server backend fullstack selfhosted !mobile -->

## Stack

| Search | Typesense (typo-tolerant in-memory search engine, typed collections, fed from the database) | Very low latency search with a strict schema and faceting |

## Project layout

```
src/search/                    collection schemas, document mapper, indexer, query function
.env.example                   TYPESENSE_HOST, TYPESENSE_PORT, TYPESENSE_API_KEY, TYPESENSE_SEARCH_KEY (placeholders)
docker-compose.yml             typesense service with a data volume
```

## Conventions

- The database is the source of truth; collections are derived and rebuilt with one reindex command.
- Collection schemas are declared in code (field name, type, `facet`, `sort`, `index`); a schema change is a new collection plus an alias switch, not an in-place edit.
- Always query through a collection alias (`products` -> `products_2026_01`) so reindexing has no downtime.
- Search-only keys are scoped (`documents:search` on one collection); a scoped key can embed a `filter_by` for the tenant.
- Queries state `query_by` explicitly with the fields and weights that matter.

## Commands

| Search up | `docker compose up -d typesense` |
| Reindex | `<run the reindex command of this project>` |

## Testing

- Integration tests use a real Typesense instance and a collection with a unique name per run, dropped afterwards.

## Rules for agents

- Never ship the admin API key to a client; use a scoped search key generated on the server.
- Never change a collection schema in place; create a new collection and move the alias.
- Always apply the tenant filter on the server side, never trust a filter sent by the client.
