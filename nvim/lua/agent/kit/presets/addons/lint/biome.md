<!-- name: Biome -->
<!-- desc: one Rust tool for lint + format (replaces ESLint and Prettier): fast, one config file -->
<!-- for: ts js -->
<!-- default: lang:typescript lang:javascript lang:bun lang:node -->

## Stack

| Lint | Biome 2 (`@biomejs/biome`): linter and formatter in one, `biome.json` | One fast tool, one config, no plugin version drift |

## Commands

| Lint | `biome check .` |
| Format | `biome check --write .` |

## Conventions

- `biome.json` is the only lint/format config: no `.eslintrc*`, no `.prettierrc*` in the repository.
- Recommended rules on, plus `noExplicitAny`, `noUnusedVariables` and `useImportType` as errors.
- Imports are sorted by Biome (organize imports); never sort them by hand.

## Quality gates

- `biome ci .` passes in CI (lint and format, no writes).

## Rules for agents

- Run `biome check --write .` before finishing; never commit unformatted files.
- Never add ESLint or Prettier next to Biome.
- Never disable a rule inline without `// biome-ignore <rule>: <reason>`.
