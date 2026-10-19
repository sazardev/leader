<!-- name: Cypress -->
<!-- desc: end-to-end and component tests in the browser with Cypress: retry-ability, cy.intercept, time travel -->
<!-- for: web ui fullstack !mobile !tui -->

## Stack

| E2E tests | Cypress (`cypress.config.ts`, `cypress/e2e/*.cy.ts`, `cy.intercept`, `cy.session`) | Interactive runner with time-travel debugging and built-in retries |

## Project layout

```
cypress.config.ts              baseUrl, e2e.specPattern, retries { runMode: 2 }, video and screenshot settings
cypress/e2e/*.cy.ts            one spec per user journey
cypress/support/commands.ts    custom commands (login through the API with cy.session)
cypress/fixtures/              stub response data
```

## Conventions

- Test user journeys from a known state; each spec creates its data through `cy.request` or a seed task, never through previous specs.
- Select by stable attributes (`data-cy`) or accessible text (`cy.contains`); not by CSS classes or position.
- Rely on retry-ability: chain assertions (`.should("be.visible")`), never `cy.wait(<ms>)`; wait on aliased requests with `cy.wait("@alias")`.
- Log in once per spec through `cy.session` with the API, not the login form each time.
- Stub third parties with `cy.intercept`; keep the app's own backend real in E2E.
- Do not store return values of commands in variables; use `.then()` or aliases.

## Commands

| E2E | `npx cypress run` |
| E2E UI | `npx cypress open` |

## Rules for agents

- Never use fixed `cy.wait(ms)` or conditional testing on unstable DOM state; fix the assertion.
- Never share state between specs or rely on spec order.
- Never commit credentials; use `Cypress.env` from `CYPRESS_*` variables.
