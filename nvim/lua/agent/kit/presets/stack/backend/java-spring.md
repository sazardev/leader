<!-- name: Java Spring Boot -->
<!-- desc: Spring Boot 3 on Java 21: hexagonal modules, Spring Data JPA, Flyway, Testcontainers, ArchUnit, Gradle -->

# STACK.md: Java Spring Boot

## Summary

A backend service on Spring Boot 3 and Java 21 (virtual threads on). Hexagonal layout per bounded context: the domain is
plain Java (records, sealed types) with no Spring or JPA annotations; web controllers and JPA repositories are adapters.
ArchUnit tests enforce the layer rules so they cannot erode silently.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Java 21 LTS | Records, sealed interfaces, pattern matching, virtual threads |
| Framework | Spring Boot 3.x (`spring-boot-starter-web`, `-validation`, `-actuator`) | Mature, huge ecosystem |
| Build | Gradle (Kotlin DSL) with a version catalog (`gradle/libs.versions.toml`) | Reproducible, typed build scripts |
| Database | PostgreSQL 16 | Relational, transactional |
| DB access | Spring Data JPA (Hibernate 6) — or jOOQ when SQL-heavy | Repositories for aggregates; jOOQ for reporting queries |
| Migrations | Flyway | Versioned SQL, applied at startup or in CI |
| Validation | Jakarta Bean Validation on request DTOs | Declarative input checks |
| Mapping | MapStruct (or hand-written mappers) | Explicit, compile-time mapping |
| API docs | `springdoc-openapi` | OpenAPI from controllers |
| Observability | Actuator + Micrometer + OpenTelemetry | Health, metrics, traces |
| Security | Spring Security (resource server / JWT) | Standard |
| Testing | JUnit 5 + AssertJ + Mockito (sparingly) + Testcontainers + `@WebMvcTest` | Layered test slices |
| Architecture tests | ArchUnit | Layer and dependency rules as tests |
| Lint / format | Spotless (palantir-java-format) + Error Prone + Checkstyle | Consistent, bug patterns caught at compile time |

## Project layout

```
settings.gradle.kts
build.gradle.kts
gradle/libs.versions.toml
src/main/java/com/acme/app/
  Application.java                         @SpringBootApplication only
  shared/
    domain/DomainException.java            base of domain errors
    web/ProblemDetailsAdvice.java          @RestControllerAdvice: domain errors → ProblemDetail, in ONE place
  <context>/                               one package per bounded context
    domain/
      Order.java                           aggregate root: invariants, no annotations
      OrderId.java                         record value object
      OrderStatus.java                     enum / sealed type
      OrderRepository.java                 port (interface)
    application/
      PlaceOrderUseCase.java               one use case per class; @Service only via config, or plain class
      PlaceOrderCommand.java               record input
    adapter/
      in/web/OrderController.java          @RestController: DTO → command → use case → response
      in/web/PlaceOrderRequest.java        record + Bean Validation
      out/persistence/OrderJpaEntity.java  @Entity (persistence model, not the domain)
      out/persistence/SpringDataOrderRepository.java  extends JpaRepository<OrderJpaEntity, UUID>
      out/persistence/JpaOrderRepository.java          implements the domain port; maps entity ↔ domain
    config/OrderConfiguration.java         @Configuration: wires use cases with ports
src/main/resources/
  application.yml
  db/migration/V1__create_orders.sql       Flyway
src/test/java/com/acme/app/
  ArchitectureTest.java                    ArchUnit layer rules
  <context>/...                            unit, slice and integration tests
```

Dependency direction: `adapter → application → domain`. `domain` imports no `org.springframework`, `jakarta.persistence` or `jakarta.validation`.

## Conventions

- One class = one responsibility; one use case per class with a single public method (`execute` / `handle`).
- Domain types are immutable where possible (records, final fields); constructors enforce invariants.
- JPA entities are separate from domain aggregates and live only in `adapter/out/persistence`.
- Controllers: validate the request DTO, build a command, call one use case, map the result. No repositories in controllers.
- `@Transactional` only on use cases (application layer), never on controllers or domain.
- Constructor injection only (no `@Autowired` fields); `final` fields.
- Errors: domain throws `DomainException` subclasses; `ProblemDetailsAdvice` maps them to RFC 9457 responses.
- New feature = domain + port → use case + test → JPA entity + adapter + Flyway migration → DTO + controller → configuration bean.

## Commands

| Task | Command |
| --- | --- |
| Run | `./gradlew bootRun` |
| Build | `./gradlew build` |
| Test | `./gradlew test` |
| Single test | `./gradlew test --tests 'com.acme.app.order.application.PlaceOrderUseCaseTest'` |
| Format | `./gradlew spotlessApply` |
| Lint / check | `./gradlew check` (Spotless, Checkstyle, Error Prone, tests, ArchUnit) |
| Migrate | `./gradlew flywayMigrate` (or on startup) |
| Dependency updates | `./gradlew dependencyUpdates` (ben-manes plugin) |

## Testing

- Domain and use cases: plain JUnit 5 + AssertJ with in-memory fake ports; no Spring context.
- Web: `@WebMvcTest(OrderController.class)` with the use case mocked; assert status, validation errors and JSON.
- Persistence: `@DataJpaTest` with Testcontainers Postgres (`@ServiceConnection`), Flyway migrations applied.
- Integration: a few `@SpringBootTest` end-to-end flows with Testcontainers.
- Architecture: ArchUnit rules (domain has no Spring/JPA imports; adapters don't depend on each other; no cycles between contexts).
- A bug fix starts with a failing test.

## Quality gates

- `./gradlew check` passes: Spotless clean, Error Prone with no warnings, Checkstyle clean, all tests and ArchUnit rules green.
- JaCoCo coverage of domain and application above 80%.
- Flyway validate passes against the migrations; Hibernate `ddl-auto=validate` (never `update`).
- OWASP dependency-check or GitHub Dependabot: no high/critical vulnerabilities.

## Dependencies

- Spring Boot starters and the BOM-managed versions first; versions in `libs.versions.toml`.
- Anything else needs a reason in the PR.
- Do NOT use: Lombok on domain types (records cover it); `ddl-auto=update`/`create` outside tests; field injection; `RestTemplate` for new code (use `RestClient`); Spring annotations inside `domain/`; JPA entities as API responses.

## Rules for agents

- Never put Spring, JPA or validation annotations in `domain/`; ArchUnit will fail.
- Never return JPA entities from controllers or use cases; map to response records.
- Every schema change is a new Flyway migration `V<n>__<change>.sql`; never edit an applied one.
- `@Transactional` belongs on use cases only.
- Use constructor injection with `final` fields; never `@Autowired` on fields.
- Map errors only in `ProblemDetailsAdvice`; never expose stack traces or SQL in responses.
- Avoid N+1: fetch joins or entity graphs for aggregates loaded with their children; check the SQL log in tests.
- Every new use case ships with a unit test; every new endpoint with a `@WebMvcTest`.
- Run `./gradlew spotlessApply check` before declaring a change done.
