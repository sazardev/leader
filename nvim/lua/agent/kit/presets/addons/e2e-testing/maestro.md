<!-- name: Maestro -->
<!-- desc: mobile UI flows in YAML for Flutter, iOS and Android apps; runs on emulators, simulators and cloud -->
<!-- for: mobile flutter swift jvm !server !tui -->

## Stack

| E2E tests | Maestro (YAML flows in `.maestro/`, run on Android emulators and iOS simulators) | Readable mobile flows without writing driver code |

## Project layout

```
.maestro/config.yaml           flows to include, tags, execution order
.maestro/flows/*.yaml          one flow per user journey (onboarding, login, checkout), starting with `appId:`
.maestro/subflows/             reusable steps (login.yaml) called with `runFlow`
```

## Conventions

- Each flow starts from a clean state (`launchApp` with `clearState: true`) and ends on a visible outcome (`assertVisible`).
- Select by accessibility identifier / semantics label first (Flutter `Semantics(identifier: ...)` or `Key`, iOS `accessibilityIdentifier`, Android `testTag`/`resource-id`), then by visible text.
- Text comes from the app's own localization; run flows in one fixed locale.
- Reusable steps go to subflows; flows take data through `env` variables, not hardcoded accounts.
- Backends for flows are a test environment with seeded data, never production.
- CI keeps the emulator image fixed and uploads the Maestro report and screenshots.

## Commands

| E2E | `maestro test .maestro/flows` |
| E2E studio | `maestro studio` |

## Rules for agents

- Never rely on fixed delays; use `assertVisible` with `extendedWaitUntil` where an animation or a request takes time.
- Never put real credentials in flows; use `env` and CI secrets.
- When a screen changes, add or update the accessibility identifier in the app, not a brittle text selector in the flow.
