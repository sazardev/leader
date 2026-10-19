<!-- name: Vitest -->
<!-- desc: fast unit and component tests on Vite: watch mode, coverage with v8, TypeScript out of the box -->
<!-- for: ts js node bun !mobile -->

## Stack

| Unit tests | Vitest (`vitest.config.ts`, `@vitest/coverage-v8`, jsdom or happy-dom for the DOM) | Fast, ESM and TypeScript native, shares the Vite config |

## Project layout

```
vitest.config.ts               test.environment, include globs, coverage thresholds, setupFiles
src/**/*.test.ts               tests next to the code they cover
test/setup.ts                  global setup: matchers, MSW server, cleanup
```

## Conventions

- Tests are named after behaviour (`it("rejects an expired token")`), arranged as arrange / act / assert, one reason to fail each.
- Test files sit beside the module (`foo.ts`, `foo.test.ts`); shared builders live in `test/factories/`.
- Fake the network at the boundary (MSW or an injected client), time with `vi.useFakeTimers()`, never real services.
- Reset state between tests (`vi.restoreAllMocks()` through `restoreMocks: true` in the config); tests never depend on order.
- Component tests use Testing Library and query by role and label, not by class or test id first.
- Coverage thresholds are set in the config and checked in CI; the number is a floor, not a goal.

## Commands

| Test | `npx vitest run` |
| Test watch | `npx vitest` |
| Coverage | `npx vitest run --coverage` |

## Quality gates

- `npx vitest run --coverage` passes with the configured thresholds.

## Rules for agents

- Every bug fix and new function gets a test that fails without the change.
- Never skip (`it.skip`, `.only`) or delete a failing test to make a run pass; fix the cause.
- Never hit the network, the real clock or the real file system without a fake.
