<!-- name: NestJS -->
<!-- desc: TypeScript API with NestJS: modules per bounded context, Prisma + Postgres, Zod, Vitest, pnpm -->

# STACK.md: NestJS

## Summary

A TypeScript backend on NestJS: dependency injection, modules and guards give structure to a large team. Each bounded
context is a Nest module with a hexagonal inside: controllers and Prisma repositories are adapters, the domain and the
use cases are plain classes that depend on ports injected by token.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Runtime | Node.js 22 LTS | Stable |
| Language | TypeScript 7 (native `tsc`), `strict: true`; fall back to 6.x if the Nest CLI / decorator metadata build lags | Types everywhere |
| Framework | NestJS 10/11 with the Fastify adapter (`@nestjs/platform-fastify`) | Modules, DI, guards, interceptors; Fastify is faster than Express |
| Validation | `zod` + `nestjs-zod` (`ZodValidationPipe`, `createZodDto`) | One schema for validation and OpenAPI |
| API docs | `@nestjs/swagger` | OpenAPI generated from DTOs |
| Database | PostgreSQL 16 | Relational, transactional |
| DB access | Prisma ORM (`prisma`, `@prisma/client`) | Typed client, declarative schema, migrations |
| Config | `@nestjs/config` + Zod schema | Validated at boot |
| Logging | `nestjs-pino` | Structured JSON, request context |
| Auth | `@nestjs/passport` or a custom guard + `@nestjs/jwt` | Guards keep auth out of handlers |
| Jobs / queues | `@nestjs/bullmq` (when needed) | Redis-backed, retries |
| Testing | Vitest (`unplugin-swc` for decorators) or Jest + `@nestjs/testing` + Supertest + Testcontainers | Unit, e2e with a real DB |
| Lint / format | ESLint (`typescript-eslint` strict-type-checked) + Prettier | Type-aware rules |
| Package manager | pnpm | Strict, fast |

## Project layout

```
src/
  main.ts                              bootstrap: Fastify adapter, global pipes/filters, swagger, shutdown hooks
  app.module.ts                        imports the context modules and infrastructure modules only
  config/config.schema.ts              Zod env schema
  shared/
    domain/domain-error.ts             DomainError base and subclasses
    http/domain-error.filter.ts        DomainError → HTTP status, in ONE place
    prisma/prisma.service.ts           PrismaClient lifecycle (onModuleInit/onModuleDestroy)
    prisma/prisma.module.ts
  <context>/                           one folder = one Nest module = one bounded context
    <context>.module.ts                binds ports to implementations ({ provide: ORDER_REPOSITORY, useClass: PrismaOrderRepository })
    domain/
      order.entity.ts                  entity + invariants (no Nest, no Prisma imports)
      order-repository.port.ts         interface + injection token
    application/
      place-order.use-case.ts          one use case per file, @Injectable, depends on ports via @Inject(token)
      place-order.use-case.spec.ts
    infrastructure/
      prisma-order.repository.ts       implements the port; maps Prisma rows ↔ entities
    http/
      orders.controller.ts             routes → use cases; no logic
      dto/place-order.dto.ts           createZodDto(schema)
prisma/
  schema.prisma                        data model
  migrations/                          generated SQL migrations
test/                                  e2e tests and Testcontainers setup
```

Dependency direction: `http → application → domain`, `infrastructure → domain`. A context never imports another context's internals: it uses that module's exported use cases or events.

## Conventions

- One file = one responsibility; Nest suffixes in names (`*.controller.ts`, `*.use-case.ts`, `*.repository.ts`, `*.port.ts`, `*.dto.ts`).
- Controllers only: route, DTO validation, call one use case, map to response DTO. No Prisma, no business rules.
- Ports are interfaces plus a `Symbol` token; use cases inject the token, modules bind the implementation.
- Prisma types never leave `infrastructure`; repositories map them to domain entities.
- Errors: domain throws `DomainError` subclasses; the global filter maps them; never throw `HttpException` from domain or application.
- Transactions: `prisma.$transaction` inside repositories or a unit-of-work port; never spread across controllers.
- Cross-context communication through exported use cases or `@nestjs/event-emitter` events, not shared repositories.
- New feature = domain + port → use case + spec → repository → DTO + controller → bind in the module.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install --frozen-lockfile` |
| Dev | `pnpm start:dev` |
| Build | `pnpm build` (`nest build`) |
| Test | `pnpm test` |
| E2E tests | `pnpm test:e2e` |
| Lint | `pnpm lint` (`eslint . --max-warnings 0`) |
| Format | `pnpm prettier --write .` |
| Prisma client | `pnpm prisma generate` |
| Migration | `pnpm prisma migrate dev --name <change>` (deploy: `pnpm prisma migrate deploy`) |

## Testing

- Use cases: unit tests building the class directly with in-memory fake ports (no Nest testing module needed).
- Controllers: `Test.createTestingModule` with the use case overridden; assert DTO validation and status codes.
- E2E: the real app with Fastify + Supertest (or `app.inject`) against Postgres in Testcontainers, migrations applied, tables truncated per test.
- Repositories: integration tests against the same container.
- A bug fix starts with a failing test; domain and application coverage above 80%.

## Quality gates

- `tsc --noEmit` clean; ESLint with `strict-type-checked`, zero warnings; Prettier check.
- Unit and e2e tests pass in CI.
- `prisma migrate diff` shows no drift between `schema.prisma` and migrations.
- `pnpm audit --prod` has no high or critical vulnerabilities.

## Dependencies

- Nest's official packages and the table above first.
- Anything else needs a reason in the PR.
- Do NOT use: TypeORM (decorated entities leak into the domain); `class-validator` together with Zod (one validation layer); Express-only middleware when a Nest guard/interceptor exists; `moment`; global `request` scoped providers without need (performance).

## Rules for agents

- Never inject `PrismaService` into controllers or use cases; only into repositories.
- Never import a Nest or Prisma symbol in `domain/`.
- Bind every port in its module with a token; never `new` an implementation inside a use case.
- Never import another context's `domain/` or `infrastructure/`; use its exported providers or events.
- Every DTO is a Zod schema; no unvalidated `@Body()` of `any` or plain interfaces.
- Throw `DomainError` subclasses; only the global filter produces HTTP errors.
- Change `schema.prisma`, then create a migration with `prisma migrate dev`; never edit an applied migration.
- Every new use case ships with a unit spec; every new endpoint with an e2e test.
- Use `pnpm` only.
