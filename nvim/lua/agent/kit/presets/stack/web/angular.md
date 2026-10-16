<!-- name: Angular (signals) -->
<!-- desc: Angular 20 standalone components, signals, new control flow, zoneless-ready, Vitest, strict TS -->

# STACK.md: Angular (signals)

## Summary

A web application on modern Angular: standalone components only (no NgModules), signals for state, the built-in control
flow (`@if`, `@for`, `@defer`), `inject()` for dependencies and the esbuild-based application builder. Features are lazy
loaded by route; services hold state as signals and talk to HTTP through typed clients.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript (the version Angular supports, strict + strictTemplates) | Typed templates |
| Framework | Angular 20 (standalone, signals, zoneless change detection where supported) | Fine-grained updates |
| Routing | Angular Router with lazy `loadComponent` / `loadChildren` | Small initial bundle |
| HTTP | `HttpClient` + `httpResource`/`resource` signals | Typed requests |
| Forms | Reactive forms (typed) or signal forms when stable | Validation in code |
| Styling | Component SCSS + design tokens as CSS custom properties | Scoped styles |
| Testing | Vitest (via `@analogjs/vitest-angular` or the CLI's builder) + Testing Library; Playwright | Fast, no Karma |
| Lint | angular-eslint + Prettier | Angular-aware rules |
| Package manager | pnpm | Strict, fast |
| Deploy | Static build to a CDN, or SSR with `@angular/ssr` | Choose per SEO need |

## Project layout

```
src/app/
  app.config.ts                    providers: router, http, zoneless
  app.routes.ts                    lazy feature routes
  core/
    http/api-client.ts             base URL, interceptors
    auth/auth.service.ts
  shared/ui/
    button/button.component.ts     standalone, OnPush, inputs as signals
  features/
    invoices/
      invoices.routes.ts
      invoice-list/invoice-list.component.ts
      invoice-list/invoice-list.component.html
      invoice-list/invoice-list.component.scss
      invoices.store.ts            signals + computed, methods that call the API
      invoices.api.ts              typed HTTP calls
      invoices.store.spec.ts
e2e/
```

Dependency direction: `features → core, shared`; features never import each other; `shared` imports nothing feature-specific.

## Conventions

- Every component standalone with `ChangeDetectionStrategy.OnPush`; inputs/outputs via `input()`/`output()`.
- State in signal stores per feature (`signal`, `computed`, explicit update methods); no `BehaviorSubject` stores.
- Templates use `@if/@for/@switch` with `track`; no `*ngIf/*ngFor`.
- `inject()` instead of constructor injection.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm ng serve` |
| Test | `pnpm ng test` (Vitest) |
| Lint | `pnpm ng lint` |
| Build | `pnpm ng build` |
| E2E | `pnpm playwright test` |
| Generate | `pnpm ng generate component features/x/y` |

## Testing

- Stores and pure functions unit-tested; components with Testing Library (what the user sees, not internals).
- HTTP mocked with `provideHttpClientTesting`; Playwright for the main flows.

## Quality gates

- `ng build` with budgets (initial < 300 KB) passes, lint clean, tests green, `strictTemplates` on.

## Dependencies

- Angular packages, Testing Library, Playwright.
- Do NOT use: NgModules for new code, NgRx for local feature state, `any` in templates, `zone.js`-dependent tricks in new code.

## Rules for agents

- Generate code with the Angular CLI schematics so files land in the right shape.
- Every new component is standalone and OnPush.
- Read state through signals; update through store methods, never by mutating arrays in place.
- Lazy load every feature route.
- Unsubscribe-free code: prefer signals/resources; if an Observable is needed, use `takeUntilDestroyed`.
- Keep templates logic-light: computed signals instead of method calls in templates.
- One component per folder with its template and styles.
- Respect the build budgets; split with `@defer` when a view grows.
