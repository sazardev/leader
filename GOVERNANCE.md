# Governance

Leader is a small, **maintainer-led** open-source project. This document says how decisions are made so contributors
know what to expect. It is deliberately short.

## Roles

- **Maintainer**: reviews and merges pull requests, cuts releases, owns the repository settings, the website and the
  security process. Currently [@sazardev](https://github.com/sazardev).
- **Contributors**: anyone who reports a bug, answers a question, improves the docs, sends a patch or tests a build. The
  commit history and the release notes are the record.
- **Community**: everyone using Leader, including people who never open an issue. Discussions and issues are the public
  square.

## How decisions are made

- **Lazy consensus**: a proposal in an issue or discussion is accepted when no maintainer objects within a reasonable
  period. Small, reversible changes can go straight to a pull request.
- **Architecture**: changes that add a new folder, a new layer, a new backend or a new dependency need an issue or a
  discussion first. Lead with the contract and the tests, not the implementation. `AGENTS.md` is the current
  architecture; a change that does not fit it needs a reason, not an exception.
- **API and keys**: user-visible keys, settings and file formats are part of the product. Do not rename or remove them
  without a deprecation path and a note in `CHANGELOG.md`.
- **Breaking changes** are marked `BREAKING CHANGE` in the commit (or `!` in the header) and get a major/minor release
  as semver requires. The changelog says what to do.
- **Releases** are cut from `master` with `chore(release): vX.Y.Z` and a tag; the changelog and the package are part of
  the release. The website deploy follows the same tag when the release includes docs.
- **Security** reports follow [SECURITY.md](SECURITY.md); the fix may be prepared privately and landed with the release.

When there is a real disagreement, the maintainer decides after hearing the arguments. That is the whole point of a
maintainer-led project: someone has to be accountable for the final call.

## Becoming a maintainer

There is no ceremony and no fixed number. A contributor who consistently sends good patches, reviews others' work,
helps in discussions and respects the Code of Conduct may be invited to become a maintainer. The invitation is public
and comes with repository access scoped to what the person actually needs. Maintainers can step down at any time; the
project will not hold a role hostage.

## Code of Conduct

Participation is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Enforcement is the maintainer's responsibility;
reports go to the private address in that file.

## Changes to this document

Open a pull request. Governance changes are small by design and are reviewed like any other contribution.
