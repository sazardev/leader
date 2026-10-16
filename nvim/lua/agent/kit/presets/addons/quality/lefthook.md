<!-- name: Lefthook git hooks -->
<!-- desc: fast git hooks: format and lint staged files on commit, Conventional Commits check on the message -->
<!-- for: all -->
<!-- default: all -->

## Stack

| Hooks | Lefthook (`lefthook.yml`): pre-commit format + lint on staged files, commit-msg Conventional Commits check | Problems caught before they reach CI, in parallel and in milliseconds |

## Project layout

```
lefthook.yml                   pre-commit: format + lint ({staged_files}); commit-msg: conventional commit check
```

## Commands

| Install hooks | `lefthook install` |

## Conventions

- Hooks run only the fast checks on staged files; tests stay in CI.
- Hooks run the same commands as the Commands table.

## Rules for agents

- Never bypass hooks with `--no-verify`.
- Commit messages follow Conventional Commits (`feat(scope): …`, `fix(scope): …`).
