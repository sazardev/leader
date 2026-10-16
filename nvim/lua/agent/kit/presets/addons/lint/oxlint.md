<!-- name: Oxlint + Prettier -->
<!-- desc: Oxlint (oxc project, Rust) for very fast linting, Prettier for formatting -->
<!-- for: ts js -->

## Stack

| Lint | Oxlint (`oxlint`, oxc project) for linting + Prettier for formatting | Lints large codebases in milliseconds; Prettier keeps formatting standard |

## Commands

| Lint | `oxlint .` |
| Format | `prettier --write .` |

## Conventions

- `.oxlintrc.json` enables the `correctness` and `suspicious` categories as errors, plus the plugins the stack uses (typescript, react, import, unicorn).
- Prettier owns formatting; Oxlint never reports style issues.
- If a type-aware rule is needed that Oxlint lacks, it is checked by `tsc --noEmit`, not by adding a second linter.

## Quality gates

- `oxlint --deny-warnings .` and `prettier --check .` pass in CI.

## Rules for agents

- Run `oxlint .` and `prettier --write .` before finishing.
- Never silence a rule inline without a comment saying why.
- Never add ESLint alongside Oxlint.
