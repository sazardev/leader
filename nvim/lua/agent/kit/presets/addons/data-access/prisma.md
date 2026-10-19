<!-- name: Prisma ORM -->
<!-- desc: schema.prisma as the source of truth, generated typed client and migrations with prisma migrate -->
<!-- for: ts js node bun !mobile -->

## Stack

| Data access | Prisma ORM (`schema.prisma`, generated Prisma Client, migrations by `prisma migrate`) | One readable schema file, a fully typed client and a mature migration flow |

## Project layout

```
prisma/schema.prisma           datasource, generator, models and enums
prisma/migrations/             generated SQL migrations, committed
src/db.ts                      the single PrismaClient instance exported to the app
```

## Conventions

- Change `schema.prisma`, then `prisma migrate dev --name <change>`; review the SQL before committing.
- One `PrismaClient` per process (cache it on `globalThis` in dev with hot reload).
- Select only the fields needed; avoid N+1 with `include`/`select` or a single `findMany` with filters.
- Multi-step writes use `prisma.$transaction`.
- Run `prisma generate` after every schema change and in CI before type checking.

## Commands

| Generate client | `npx prisma generate` |
| Migrate | `npx prisma migrate deploy` |
| Studio | `npx prisma studio` |

## Dependencies

- `prisma` as a dev dependency, `@prisma/client` as a dependency.

## Rules for agents

- Never run `prisma migrate reset` or `db push` against anything but a local database.
- Never use `$queryRawUnsafe` / `$executeRawUnsafe` with user input; use the tagged `$queryRaw` template.
- Never edit an applied migration; create a new one.
