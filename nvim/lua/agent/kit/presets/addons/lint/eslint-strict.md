<!-- name: ESLint strict + Prettier -->
<!-- desc: ESLint flat config with typescript-eslint strictTypeChecked, Prettier for formatting -->
<!-- for: ts js -->

## Stack

| Lint | ESLint 9 flat config (`eslint.config.js`) + `typescript-eslint` `strictTypeChecked` + Prettier | Type-aware rules catch floating promises, unsafe `any` and misuse of APIs |

## Commands

| Lint | `eslint .` |
| Format | `prettier --write .` |

## Conventions

- One `eslint.config.js`; type-aware linting through `parserOptions.projectService`.
- `eslint-config-prettier` turns off every formatting rule: Prettier formats, ESLint finds bugs.
- `@typescript-eslint/no-floating-promises`, `no-misused-promises` and `switch-exhaustiveness-check` are errors.

## Quality gates

- `eslint . --max-warnings 0` and `prettier --check .` pass in CI.

## Rules for agents

- Fix lint errors; never add `eslint-disable` without a rule name and a reason.
- Never lower a rule's severity in the config to make a change pass.
