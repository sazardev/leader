<!-- name: Dev container -->
<!-- desc: reproducible development environment in .devcontainer, same tools for everyone and for agents -->
<!-- for: all -->

## Stack

| Dev | Dev Container (`.devcontainer/devcontainer.json`): toolchain, CLIs and services pinned in one image | Same environment on every machine, in Codespaces and for coding agents |

## Project layout

```
.devcontainer/
  devcontainer.json            image or Dockerfile, features, postCreateCommand (install deps), forwarded ports
```

## Conventions

- Tool versions in the dev container match CI.
- `postCreateCommand` installs dependencies so the Commands table works right after opening.
- Services the app needs locally (database, cache) run through compose referenced by the dev container.

## Rules for agents

- A new tool the project needs is added to the dev container in the same change.
- Never depend on something installed only on one developer's machine.
