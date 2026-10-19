<!-- name: OpenFeature flags -->
<!-- desc: vendor-neutral feature flags: one SDK API, any provider (flagd, LaunchDarkly, Unleash), typed defaults -->
<!-- for: all -->

## Stack

| Feature flags | OpenFeature (vendor-neutral SDK; provider such as flagd, Unleash or a hosted service) | Roll out and kill features without a deploy and without lock-in to one vendor |

## Project layout

```
src/flags/                     provider registration, evaluation context builder, typed flag helpers (name per language)
src/flags/catalog              flag keys, type and default value, owner and removal date
```

## Conventions

- Flags are evaluated through the OpenFeature client only (`getBooleanValue(key, default, context)`); no vendor SDK in feature code.
- Every flag has a typed default that is the safe, current behaviour; evaluation never throws into the caller.
- The evaluation context holds an opaque user or tenant id and coarse attributes (plan, country), never personal data.
- Flag keys live in one catalog with an owner and an expiry; a flag is removed (code and config) once fully rolled out.
- Evaluate once per request or screen and pass the result down; avoid scattering the same flag in many places.
- Tests use the in-memory provider and set flags explicitly per case.

## Rules for agents

- Never branch on a flag key that is not in the catalog.
- Never guard security checks or data migrations behind a flag that can be flipped at runtime.
- Never leave a flag in place after its rollout is done; delete both branches' dead code.
