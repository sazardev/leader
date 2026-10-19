<!-- name: Search endpoint -->
<!-- desc: search with filters, sorting, pagination and ranking, with safe query handling -->
<!-- for: server -->
<!-- input: what | What is searched (e.g. products, customers) -->
<!-- input: fields | Fields searched and filters offered (e.g. name and description; filter by status, price range) -->

# Recipe: search for {{what}}

Searched and filtered: {{fields}}.

## Make

- A search operation on the project's API (route, RPC, controller) taking a text query, the filters, a sort and a page, registered where the others are.
- The query with what STACK.md's Search or Database row gives: full-text search of the database (Postgres `tsvector`, SQLite FTS5, MySQL fulltext) or the search engine the project uses; a migration for the index when needed.
- Ranking: matches in the main field first, then the others; ties broken by a stable key so pages never overlap.
- Pagination with a limit (default and maximum) and a total or a cursor; filters combined with AND; a sort among a fixed set of fields.
- A response type with the page, the count and, when cheap, the matched text.

## Rules

- Parameterized queries only; the sort field and direction come from an allow-list, never from the raw input.
- Escape the query's wildcard and operator characters, trim it, cap its length; an empty query lists by the default sort.
- Only what the caller may see is searched: apply the same authorization as the plain list.
- Invalid filters answer 400 with the field; no matches is an empty page, not an error.
- Follow the existing endpoints: naming, response shape, error mapping.

## Tests

- A match in each searched field, a ranking order, a combination of filters, a sort.
- Pagination: first page, last page, no overlap between pages, a limit above the maximum.
- Hostile input: quotes, wildcards, a very long query, an unknown sort field.
