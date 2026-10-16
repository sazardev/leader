<!-- name: Forgejo / Gitea Actions -->
<!-- desc: GitHub-Actions-compatible workflows on a self-hosted forge, with your own runner -->
<!-- for: all -->

## Stack

| CI | Forgejo (or Gitea) Actions on a self-hosted forge, `.forgejo/workflows/ci.yml`, own `forgejo-runner` | CI on infrastructure you own, same workflow syntax as GitHub Actions |

## Project layout

```
.forgejo/workflows/ci.yml      jobs: lint, test, build (runs-on: the label of your runner)
```

## Conventions

- Workflows use only actions mirrored or reachable from the forge; versions pinned.
- The runner runs jobs in containers (Docker/Podman), never directly on the host.
- The default branch is protected and requires the CI status to pass.

## Rules for agents

- Never weaken a CI step to make a change pass.
- Never put secrets in workflow files; use the repository's secrets.
