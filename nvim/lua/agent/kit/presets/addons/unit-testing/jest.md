<!-- name: Jest -->
<!-- desc: unit and component tests with Jest: mocks, snapshots, coverage; ts-jest, SWC or Babel transform -->
<!-- for: ts js node !mobile -->

## Stack

| Unit tests | Jest (`jest.config.ts`, `@swc/jest` or `ts-jest` transform, `jest-environment-jsdom` for the DOM) | The most widely used runner, large ecosystem, built-in mocks and coverage |

## Project layout

```
jest.config.ts                 testEnvironment, transform, moduleNameMapper, coverageThreshold, setupFilesAfterEnv
src/**/*.test.ts               tests next to the code they cover
test/setup.ts                  global setup: matchers, network fake, cleanup
```

## Conventions

- Tests are named after behaviour (`it("rejects an expired token")`) and arranged as arrange / act / assert.
- Test files sit beside the module; shared builders live in `test/factories/`.
- Fake the network at the boundary (MSW or an injected client), time with `jest.useFakeTimers()`.
- `restoreMocks: true` and `clearMocks: true` in the config; tests never depend on order or on each other.
- Snapshots only for small, stable output; large or volatile snapshots are replaced by explicit assertions.
- Component tests use Testing Library and query by role and label.
- `coverageThreshold` is enforced in CI.

## Commands

| Test | `npx jest --ci` |
| Test watch | `npx jest --watch` |
| Coverage | `npx jest --ci --coverage` |

## Quality gates

- `npx jest --ci --coverage` passes with the configured thresholds.

## Rules for agents

- Every bug fix and new function gets a test that fails without the change.
- Never use `.skip` or `.only`, or update a snapshot blindly, to make a run pass; read the diff.
- Never hit the network, the real clock or the real file system without a fake.
