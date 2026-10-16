<!-- name: Git workflow -->
<!-- desc: Conventional Commits, small atomic commits, short-lived branches, small PRs, CI green before merge -->

### Git workflow

- **Conventional Commits**: `type(scope): summary` in imperative mood, ≤ 72 characters (`feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `build`, `ci`); `!` or `BREAKING CHANGE:` for breaking changes.
- **Atomic commits**: one logical change each, building and passing tests on its own; refactors separate from behaviour changes.
- **Short-lived branches** off the main branch (trunk-based), merged within days; rebase or merge main often.
- **Small PRs**: aim under ~400 changed lines; larger work is split or hidden behind a feature flag.
- **The body explains why** when it is not obvious: the problem, the decision, links to issues.
- **No noise**: no unrelated formatting, no generated or build artifacts unless they are meant to be committed, no secrets, no debug leftovers.
- **CI must pass** before merge (build, lint, tests); never merge red or skip hooks.
- **History is for readers**: squash fixup commits before merging; never rewrite shared history.
- Review check: each commit message matches the convention and the diff contains only what the message says.
