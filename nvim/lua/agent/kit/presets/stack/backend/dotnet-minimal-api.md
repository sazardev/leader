<!-- name: .NET minimal API -->
<!-- desc: C# .NET 9 minimal APIs in vertical slices: EF Core or Dapper, FluentValidation-free, xUnit, analyzers -->

# STACK.md: .NET minimal API

## Summary

An HTTP API on ASP.NET Core minimal APIs, organised in **vertical slices**: each feature folder holds its endpoint, request
and response types, handler and validation. The domain is plain C# with no framework types; persistence is an adapter
(EF Core for rich models, Dapper for query-heavy slices). Nullable reference types and analyzers are on and warnings are errors.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | C# 13 on .NET 9 (move to .NET 10 LTS when it ships in your environment) | Fast runtime, strong typing |
| Web | ASP.NET Core minimal APIs + route groups | Little ceremony, typed results |
| Data | PostgreSQL 16 + EF Core 9 (Npgsql) or Dapper | EF for aggregates, Dapper for reads |
| Validation | `System.ComponentModel.DataAnnotations` + endpoint filters | Built in, no reflection magic |
| Errors | `ProblemDetails` (RFC 9457) via `AddProblemDetails` | One error format |
| OpenAPI | `Microsoft.AspNetCore.OpenApi` | Built-in document generation |
| Logging | `ILogger` + OpenTelemetry exporter | Structured, standard |
| Testing | xUnit + `WebApplicationFactory` + Testcontainers | Real HTTP and real Postgres |
| Lint | .NET analyzers (`AnalysisLevel=latest-all`) + `dotnet format` | Built in |
| Deploy | Container from `dotnet publish /t:PublishContainer` | No Dockerfile needed |

## Project layout

```
src/Api/
  Program.cs                     composition root: services, middleware, MapEndpoints()
  Features/
    Invoices/
      CreateInvoice.cs           endpoint + request/response records + handler for ONE use case
      GetInvoice.cs
      InvoicesModule.cs          MapGroup("/invoices") registering the slice's endpoints
  Domain/
    Invoice.cs                   entity with its invariants (no EF attributes)
    Money.cs                     value object
    DomainError.cs
  Infrastructure/
    AppDbContext.cs
    Configurations/InvoiceConfiguration.cs   EF mapping (IEntityTypeConfiguration)
    Migrations/
tests/Api.Tests/
  Features/Invoices/CreateInvoiceTests.cs
  ApiFactory.cs                  WebApplicationFactory + Testcontainers Postgres
Directory.Build.props            Nullable, TreatWarningsAsErrors, analyzers
```

Dependency direction: `Features → Domain`, `Features → Infrastructure` through `AppDbContext`; `Domain` references nothing.

## Conventions

- One file per use case in `Features/<Area>/`; records for requests/responses; `TypedResults` for responses.
- Handlers are static methods taking their dependencies as parameters (DI resolves them); no MediatR.
- Domain methods enforce invariants and return results or throw `DomainError`, mapped to ProblemDetails in one middleware.
- `CancellationToken` flows through every async call.
- New feature = domain change → slice file → module registration → tests.

## Commands

| Task | Command |
| --- | --- |
| Restore | `dotnet restore` |
| Run | `dotnet run --project src/Api` |
| Build | `dotnet build -warnaserror` |
| Test | `dotnet test` |
| Format | `dotnet format` |
| Migration | `dotnet ef migrations add <Name> --project src/Api` |
| Publish | `dotnet publish src/Api -c Release /t:PublishContainer` |

## Testing

- Integration tests per slice through `WebApplicationFactory` against Testcontainers Postgres; assert status, body and DB state.
- Domain unit tests for invariants (no mocks needed).
- One test class per use case file.

## Quality gates

- `dotnet build -warnaserror` with nullable enabled and analyzers at `latest-all`; `dotnet format --verify-no-changes`.
- `dotnet test` green; migrations generated and committed with the change that needs them.

## Dependencies

- ASP.NET Core, EF Core/Npgsql or Dapper, OpenTelemetry, xUnit, Testcontainers.
- Do NOT use: MediatR (a slice calls its handler directly), AutoMapper (map explicitly), repository wrappers over EF's `DbSet`.

## Rules for agents

- Never return entities from endpoints: map to response records.
- Never put EF attributes on domain types; mapping lives in `Configurations/`.
- Every endpoint has a typed result union (`Results<Ok<T>, NotFound, ValidationProblem>`).
- Pass `CancellationToken` to every async EF/Dapper call.
- No `async void`, no `.Result`/`.Wait()`.
- Errors leave as ProblemDetails; no custom error JSON.
- Keep one use case per file; a file over ~200 lines is two use cases.
- Add the migration in the same change as the model change.
