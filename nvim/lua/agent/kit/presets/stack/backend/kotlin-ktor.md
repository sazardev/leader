<!-- name: Kotlin Ktor -->
<!-- desc: Kotlin API: Ktor + coroutines, Exposed (or jOOQ) + Flyway, Koin, kotlinx.serialization, kotest, detekt -->

# STACK.md: Kotlin Ktor

## Summary

A lightweight Kotlin backend on Ktor with coroutines end to end. Routing and serialization are explicit (no
classpath scanning), Koin wires dependencies, Exposed (DSL) or jOOQ talks to Postgres. Hexagonal layout per feature:
the domain is plain Kotlin (data/value classes, sealed results) with no framework imports.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Kotlin 2.x on JDK 21 | Null safety, coroutines, value classes |
| Framework | Ktor 3 server (Netty or CIO engine) | Explicit, coroutine-native, small |
| Serialization | `kotlinx.serialization` (ContentNegotiation) | Compile-time, no reflection |
| Validation | Ktor `RequestValidation` plugin + value class constructors | Invalid input rejected at the edge |
| DI | Koin (`koin-ktor`) | Simple, no codegen |
| Database | PostgreSQL 16 | Relational, transactional |
| DB access | Exposed DSL (`exposed-core`, `exposed-jdbc` or `exposed-r2dbc`) — jOOQ when SQL-heavy | Typed SQL; DSL over DAO |
| Connection pool | HikariCP | Standard |
| Migrations | Flyway | Versioned SQL |
| Config | `application.conf` (HOCON) + env overrides, mapped to data classes | Typed config |
| Logging | Logback + `kotlin-logging`, JSON encoder in prod | Structured logs, MDC per call |
| Observability | Ktor `CallId`, `CallLogging`, Micrometer metrics, OpenTelemetry agent | Request tracing |
| Testing | kotest (+ `kotest-assertions`) + MockK (sparingly) + Ktor `testApplication` + Testcontainers | Expressive tests |
| Lint / format | detekt + ktlint (via `ktlint-gradle` or Spotless) | Style and smell checks |
| Build | Gradle Kotlin DSL + version catalog | Reproducible |

## Project layout

```
build.gradle.kts
gradle/libs.versions.toml
src/main/kotlin/com/acme/app/
  Application.kt                     main + Application.module(): install plugins, Koin modules, routing
  plugins/                           one file per plugin setup (Serialization.kt, StatusPages.kt, Monitoring.kt, Security.kt)
  shared/
    DomainError.kt                   sealed hierarchy of domain errors
    db/Database.kt                   Hikari data source, Flyway, dbQuery { } suspend helper (Dispatchers.IO)
  <feature>/
    domain/
      Order.kt                       entity + invariants
      OrderId.kt                     @JvmInline value class
      OrderRepository.kt             port (interface with suspend funs)
    application/
      PlaceOrder.kt                  one use case per file: class with operator suspend fun invoke
    infrastructure/
      OrdersTable.kt                 Exposed table object
      ExposedOrderRepository.kt      implements the port; maps rows ↔ entities
    http/
      OrderRoutes.kt                 Route.orderRoutes(): request → use case → response
      OrderDtos.kt                   @Serializable request/response classes
    OrderModule.kt                   Koin module of the feature
src/main/resources/
  application.conf
  db/migration/V1__create_orders.sql
src/test/kotlin/...                  mirrors main
```

Dependency direction: `http → application → domain`, `infrastructure → domain`. `domain` imports no Ktor, Exposed or Koin.

## Conventions

- One file = one responsibility; one use case per file, one route group per feature.
- Value classes for ids and validated values; data classes for entities with invariants in `init` or factory functions.
- Routes are thin: receive DTO, call one use case, respond. No Exposed calls in routes.
- All DB access inside `dbQuery { }` (suspending, on `Dispatchers.IO`); transactions in the use case through a transaction port when several repositories are involved.
- Errors: use cases return or throw `DomainError`; `StatusPages` maps them to HTTP status in ONE place.
- Structured concurrency: no `GlobalScope`; background work uses the application's scope.
- New feature = domain + port → use case + test → table + repository + migration → DTOs + routes → Koin module → register in `Application.module`.

## Commands

| Task | Command |
| --- | --- |
| Run | `./gradlew run` (auto-reload: `./gradlew -t build` + `development = true`) |
| Build | `./gradlew build` |
| Fat jar | `./gradlew buildFatJar` (Ktor plugin) |
| Test | `./gradlew test` |
| Single test | `./gradlew test --tests 'com.acme.app.order.application.PlaceOrderTest'` |
| Lint | `./gradlew detekt ktlintCheck` |
| Format | `./gradlew ktlintFormat` |
| Migrate | `./gradlew flywayMigrate` (or on startup) |

## Testing

- Domain and use cases: kotest specs (`FunSpec`/`BehaviorSpec`) with in-memory fake repositories; `runTest` for coroutines.
- Routes: `testApplication { }` with Koin overridden by fakes; assert status and decoded JSON.
- Repositories: integration tests against Postgres in Testcontainers (kotest extension), Flyway applied, tables truncated per test.
- Prefer fakes over MockK; mock only third-party clients.
- A bug fix starts with a failing test; Kover coverage of domain and application above 80%.

## Quality gates

- `./gradlew check` passes: detekt (zero issues, `buildUponDefaultConfig`), ktlint, tests.
- Compiler with `allWarningsAsErrors = true`.
- Flyway validate passes; no schema changes outside migrations.
- Dependency updates and vulnerabilities checked (Dependabot / `dependencyUpdates`).

## Dependencies

- Ktor's official plugins and kotlinx libraries first; versions in `libs.versions.toml`.
- Anything else needs a reason in the PR.
- Do NOT use: Jackson alongside kotlinx.serialization; Exposed DAO entities in the domain; `runBlocking` in request handling; `GlobalScope`; Spring on top of Ktor; reflection-based DI containers.

## Rules for agents

- Never call `runBlocking` inside routes or use cases; everything is `suspend`.
- Never import Ktor, Exposed or Koin in `domain/`.
- Every DB call goes through `dbQuery { }`; never block a Netty event-loop thread.
- Request/response classes are `@Serializable` DTOs; never serialize domain entities directly.
- Map errors only in the `StatusPages` plugin; never leak exception messages to clients.
- Every schema change is a Flyway migration; never edit an applied one.
- Register new dependencies in the feature's Koin module; never instantiate infrastructure inside use cases.
- Every new use case ships with a kotest spec; every new route with a `testApplication` test.
- Run `./gradlew ktlintFormat check` before declaring a change done.
