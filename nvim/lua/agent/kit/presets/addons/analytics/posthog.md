<!-- name: PostHog -->
<!-- desc: product analytics with events, funnels and session replay; consent-aware, identified by an opaque id -->
<!-- for: all -->

## Stack

| Analytics | PostHog (product analytics: typed events, funnels, retention; cloud or self-hosted) | One tool for events, funnels and replays |

## Project layout

```
src/analytics/                 the only module that imports the PostHog SDK: track, identify, reset (name per language)
src/analytics/events.ts        the event catalog: names and property types
.env.example                   POSTHOG_KEY, POSTHOG_HOST (project key is public; personal API keys are not)
```

## Conventions

- Events come from one catalog with names like `object_action` (`invoice_sent`) and typed properties; call sites cannot invent names.
- Identify users by an opaque internal id; no emails, names or free text in properties.
- Analytics starts only after consent where the law requires it; `opt_out_capturing()` honours a refusal and `reset()` runs on logout.
- Analytics is disabled when no key is set (local, tests, CI).
- Server-side events for money or security facts; client events only for UI behaviour.
- Session replay masks all inputs and sensitive elements by default.

## Rules for agents

- Never send personal data, secrets or message contents as event properties.
- Never call the SDK outside `src/analytics/`.
- Never block a user action on an analytics call; failures are swallowed.
