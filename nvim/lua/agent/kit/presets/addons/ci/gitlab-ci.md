<!-- name: GitLab CI -->
<!-- desc: .gitlab-ci.yml with lint, test and build stages, caches and merge request pipelines -->
<!-- for: all -->

## Stack

| CI | GitLab CI (`.gitlab-ci.yml`), merge request pipelines | Quality gates on every merge request, in the same place as the code |

## Project layout

```
.gitlab-ci.yml                 stages: lint, test, build; cache per lockfile; rules: merge requests and the default branch
```

## Conventions

- Jobs run the commands from the Commands table; images are pinned to a version tag (never `latest`).
- `workflow: rules` avoid duplicate branch + merge request pipelines; `interruptible: true` cancels superseded runs.
- Protected variables hold secrets; the default branch requires a successful pipeline to merge.

## Rules for agents

- Never skip or `allow_failure` a quality job to make a change pass.
- Never write secrets into `.gitlab-ci.yml`.
