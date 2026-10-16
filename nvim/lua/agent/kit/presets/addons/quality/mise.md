<!-- name: mise (tool versions) -->
<!-- desc: pin language runtimes and CLIs per project in mise.toml; same versions locally and in CI -->
<!-- for: all -->

## Stack

| Dev | mise (`mise.toml`): pinned runtimes and CLIs, project env vars, tasks | One file decides every tool version; no version drift between machines |

## Project layout

```
mise.toml                      [tools] runtime and CLI versions; [env] non-secret defaults
```

## Commands

| Install tools | `mise install` |

## Conventions

- Every tool in the Commands table has its version pinned in `mise.toml`.
- CI installs tools with mise too, so it uses the same versions.

## Rules for agents

- Change a tool version only in `mise.toml`, never by documenting a global install.
- Never put secrets in `mise.toml`.
