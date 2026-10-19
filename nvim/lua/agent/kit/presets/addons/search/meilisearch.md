<!-- name: Meilisearch -->
<!-- desc: typo-tolerant full-text search with facets, fed from the database, one small binary -->
<!-- for: server backend fullstack selfhosted !mobile -->

## Stack

| Search | Meilisearch (typo-tolerant full-text index fed from the database) | Fast relevant search with facets and little configuration |

## Project layout

```
src/search/                    index settings, document mapper, indexer, query function
.env.example                   MEILI_URL, MEILI_MASTER_KEY, MEILI_SEARCH_KEY (placeholders)
docker-compose.yml             meilisearch service with a volume for its data
```

## Conventions

- The database is the source of truth; the index is derived and can be rebuilt from scratch with one command.
- One index per searchable entity; the primary key is the entity id; documents hold only searchable and displayable fields.
- Index settings (`searchableAttributes`, `filterableAttributes`, `sortableAttributes`, ranking rules) live in code and are applied at deploy time.
- Writes are sent in batches and asynchronously; wait for the returned task only in tests and in the reindex command.
- The browser uses a search-only API key, or a tenant token that embeds the filter of what the user may see.

## Commands

| Search up | `docker compose up -d meilisearch` |
| Reindex | `<run the reindex command of this project>` |

## Testing

- Integration tests use a real Meilisearch instance with a unique index prefix per run, and wait for tasks before asserting.

## Rules for agents

- Never expose the master key; clients get a search key or a tenant token only.
- Never index fields the user must not see (secrets, other tenants' data); filter by tenant in every query.
- Never read from the index as if it were the source of truth for writes.
