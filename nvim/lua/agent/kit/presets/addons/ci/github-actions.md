<!-- name: GitHub Actions -->
<!-- desc: one workflow per pull request: format, lint, typecheck, tests, build; caches; pinned actions -->
<!-- for: all -->
<!-- default: all -->

## Stack

| CI | GitHub Actions (`.github/workflows/ci.yml`) on every pull request and push to `main` | Runs the same quality gates as local, next to the code review |

## Project layout

```
.github/workflows/ci.yml       jobs: lint (format + lint + typecheck), test, build; dependency cache; concurrency per branch
```

## Conventions

- CI runs exactly the commands in the Commands table; no CI-only scripts.
- Third-party actions are pinned to a full commit SHA; `permissions:` default to `contents: read`.
- `concurrency` cancels superseded runs on the same branch; `main` is protected and requires a green CI.

## Rules for agents

- Never weaken or skip a CI step to make a change pass.
- A new quality gate is added to the Commands table and to `ci.yml` in the same change.
- Never put secrets in workflow files; use repository or environment secrets.
