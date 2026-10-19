# Release kit (`<leader>GR`)

The steps around a release that are always the same, inside a git repository. Changelog and checklist cost 0 tokens; the
PR description is one light-tier request. Nothing is ever tagged, pushed, posted or published from here: those lines
are shown for you to run. Keys: [`CHEATSHEET.md`](../../CHEATSHEET.md) (section **Git**, `release …`).

## Changelog (`c`)

Reads the commits since the last tag (all of them before the first tag), in Conventional Commits:

| Commits since the tag | Next version |
|---|---|
| a breaking change (`feat!:`, `refactor(api)!:`, or `BREAKING CHANGE:` in the body) | major (minor before 1.0) |
| a `feat` | minor |
| anything else | patch |

The current version is read from `VERSION`, then `package.json`, `pubspec.yaml`, `Cargo.toml`, `pyproject.toml`, then
the last tag. The confirmation shows the section; **Write** puts it at the top of `CHANGELOG.md` (the file is created with
a header when missing; a section of the same version is replaced, never duplicated). Groups: Breaking changes,
Features, Fixes, Performance, Other changes (each commit once, in the first group it fits); scopes in bold, short hashes
at the end. Release commits (`chore(release): …`) and merges are left out.

Then, by hand: bump the version file, commit, `git tag vX.Y.Z`, `git push --tags`.

## PR description (`p`)

The branch against its base (`origin/HEAD`, else `origin/main`, `origin/master`, `main`, `master`): its commit subjects,
the diff stat and the diff (cut at `settings.git.release.pr_max_chars`, 12000) go to the light model, which writes
**Summary · Changes · How to test · Risks** from what they show, never inventing tickets or behaviour. The body opens in a
split and is copied to the clipboard: paste it in the PR (`gh pr create --body "$(…)"` or the web form).

## Checklist (`l`)

A buffer of what must be true before releasing, checked where it can be:

- **Repository**: working tree clean, ahead/behind the upstream.
- **Quality gates**: the commands in STACK.md's `## Quality gates` (or the test/lint/format/build ones of `## Commands`);
  `⏎` runs one in the integrated terminal. A command that leaves the machine (push, deploy, publish, release, upload,
  tag) is listed "by hand" and never runs from here.
- **Version and changelog**: whether CHANGELOG.md has the next version (`⏎` writes it), what the version file says
  against the next version (`⏎` opens it), the tag line to run.
- **Shipping**: the CI configuration found (GitHub, GitLab, Forgejo/Gitea, CircleCI) and STACK.md's Deploy / Release /
  Hosting / Distribution / CI rows.

`r` reads it again, `q` closes.

## Pitfalls

- Subjects that are not Conventional Commits still appear, under Other changes, and never bump more than a patch: keep
  using the commit panel (`<leader>Gc`), which validates them.
- The changelog follows tags: tag every release, or the next changelog includes the previous one's commits.
