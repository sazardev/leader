<!-- name: Plausible -->
<!-- desc: cookie-less privacy-friendly web analytics: page views, goals and custom events, no consent banner -->
<!-- for: web ui fullstack selfhosted !mobile -->

## Stack

| Analytics | Plausible (cookie-less, privacy-friendly page and goal analytics; cloud or self-hosted) | Simple traffic numbers without personal data or a consent banner |

## Project layout

```
src/analytics/                 the only place that loads the Plausible script and sends custom events
.env.example                   PLAUSIBLE_DOMAIN, PLAUSIBLE_SRC (placeholders)
```

## Conventions

- Load the script with `defer` and `data-domain`; for single-page apps use the script variant that tracks `pushState` navigation.
- Goals are custom events (`plausible("Signup")`) with a short documented list of names; props carry only non-personal values such as plan or source.
- Proxy the script and event endpoint through our own domain when ad blockers must not hide real traffic.
- Disabled outside production (no `data-domain` in dev and tests).
- Goals are created in the Plausible dashboard first; a code event without a goal is not shown.

## Rules for agents

- Never add props with emails, user ids or free text; Plausible must stay free of personal data.
- Never add cookies or local storage identifiers for analytics.
- Never load the analytics script in development or tests.
