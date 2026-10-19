<!-- name: Playwright -->
<!-- desc: end-to-end browser tests with Playwright: auto-waiting locators, traces, fixtures, parallel CI -->
<!-- for: web ui fullstack !mobile !tui -->

## Stack

| E2E tests | Playwright Test (`playwright.config.ts`, Chromium + Firefox + WebKit, trace viewer) | Reliable cross-browser flows with auto-waiting and great debugging |

## Project layout

```
playwright.config.ts           baseURL, projects, webServer (starts the app), retries on CI, trace: "on-first-retry"
e2e/*.spec.ts                  one spec per user journey (signup, checkout)
e2e/fixtures.ts                custom fixtures: logged-in page, seeded data
e2e/pages/                     page objects for screens with many steps
```

## Conventions

- Test user journeys, not components: each spec starts from a known state and finishes on a visible outcome.
- Locators by role, label and text (`getByRole`, `getByLabel`); `data-testid` only when nothing semantic exists.
- Rely on auto-waiting and web-first assertions (`await expect(locator).toBeVisible()`); never `waitForTimeout`.
- Tests are independent and parallel: each creates its own data through the API or a seed fixture, and logs in by reusing saved `storageState`.
- The network stays real for the app's own backend; third parties are stubbed with `page.route`.
- Failures keep trace, screenshot and video as CI artifacts (`playwright-report/`).

## Commands

| E2E | `npx playwright test` |
| E2E UI | `npx playwright test --ui` |
| E2E install | `npx playwright install --with-deps` |

## Rules for agents

- Never use fixed sleeps or CSS/XPath chains tied to layout; fix the locator or the missing wait.
- Never share state or order between specs; never log in through the UI in every test.
- Never put real credentials in specs; use environment variables and test accounts.
