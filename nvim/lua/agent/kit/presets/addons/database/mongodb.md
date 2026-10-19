<!-- name: MongoDB -->
<!-- desc: document database with schema validation, explicit indexes and a real server in tests -->
<!-- for: server backend fullstack selfhosted !mobile -->

## Stack

| Database | MongoDB 8 (`MONGODB_URI`, schema validation, explicit indexes) | Documents that map to the domain's aggregates, flexible evolving shapes |

## Project layout

```
db/indexes/                    index definitions created by a script, versioned with the code
db/validators/                 JSON Schema validators per collection
compose.yaml                   local `mongo` service with a named volume
```

## Conventions

- Connection string from `MONGODB_URI`; one client per process, reused.
- One collection per aggregate; embed what is always read together, reference what grows without bound.
- Declare a JSON Schema `validator` per collection and create every index in code, never by hand.
- Every query has an index that supports it; check with `explain("executionStats")`.
- Operators come from typed query builders; request bodies are never passed as a filter object.

## Commands

| Database up | `docker compose up -d mongo` |
| Shell | `mongosh "$MONGODB_URI"` |

## Testing

- Integration tests run against a real MongoDB (container), each with its own database name that is dropped afterwards.

## Rules for agents

- Never pass user input straight into a query filter: operators like `$where` or `$ne` can be injected; validate and cast first.
- Never create unbounded arrays inside a document.
- Never run `dropDatabase` or `deleteMany({})` outside tests.
