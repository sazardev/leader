<!-- name: Renovate -->
<!-- desc: automated dependency updates: grouped, scheduled, patch updates automerged when CI is green -->
<!-- for: all -->
<!-- default: all -->

## Stack

| Updates | Renovate (`renovate.json`): grouped weekly updates, automerge for patch and lockfile maintenance | Dependencies stay current in small, reviewable steps |

## Project layout

```
renovate.json                  extends config:recommended; schedule; packageRules: groups, automerge patch
```

## Conventions

- Related packages update together (framework + its plugins, test tooling, linters).
- Patch updates and lockfile maintenance automerge only when CI is green; minor/major are reviewed.
- A major update gets its own pull request with the migration notes linked.

## Rules for agents

- Never pin a dependency to an old version to silence Renovate without a comment saying why.
- Never mix a dependency update with feature changes in one commit.
