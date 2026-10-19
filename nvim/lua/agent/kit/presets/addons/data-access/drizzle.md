<!-- name: Drizzle ORM -->
<!-- desc: TypeScript schema as code, SQL-like queries and generated migrations with drizzle-kit -->
<!-- for: ts js node bun !mobile -->

## Stack

| Data access | Drizzle ORM (schema in TypeScript, queries typed from it, migrations by `drizzle-kit`) | SQL stays visible, types come from the schema, no codegen step at runtime |

## Project layout

```
drizzle.config.ts              dialect, schema path, migrations folder, DATABASE_URL
src/db/schema.ts               tables, relations and enums: the single source of the schema
src/db/index.ts                the one database client (pool) exported to the app
drizzle/                       generated SQL migrations, committed
```

## Conventions

- Change `schema.ts`, then `drizzle-kit generate`; review the SQL before committing it.
- Queries live in repository/query modules, not in route handlers or components.
- Use the query builder or `sql` template with parameters; `sql.raw` is never fed user input.
- Multi-step writes go inside `db.transaction`.
- Infer row types with `typeof table.$inferSelect` / `$inferInsert` instead of rewriting them.

## Commands

| Generate migration | `npx drizzle-kit generate` |
| Migrate | `npx drizzle-kit migrate` |
| Studio | `npx drizzle-kit studio` |

## Dependencies

- `drizzle-orm` and a driver for the database; `drizzle-kit` as a dev dependency.

## Rules for agents

- Never edit a generated migration that was already applied; generate a new one.
- Never use `drizzle-kit push` against staging or production; it skips migration history.
- Never interpolate user input into `sql.raw`.
