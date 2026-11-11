# Contributing to Leader

Thanks for taking the time to make Leader better. This guide is the short path. The architecture, the contracts and the
pitfalls for whoever touches the config (people or agents) are in [AGENTS.md](AGENTS.md); read the part that matches
your change before opening a pull request.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md). Be kind, assume good faith and critique code,
not people.

## Ways to help

- **Report a bug** with the [bug template](https://github.com/sazardev/leader/issues/new?template=bug_report.yml). A
  minimal reproduction is worth more than a long description.
- **Ask or answer** in [Discussions](https://github.com/sazardev/leader/discussions): setup questions, ideas, what you
  built with Leader, what you would like to see.
- **Improve the docs**: README, `CHEATSHEET.md` (generated, edit the keymaps), `docs/cheatsheets/`, the guide for your
  language. Documentation fixes are as welcome as code.
- **Send a language pack, a plugin, a key or a fix**: one file per responsibility, tests where the contract is pure.
- **Test on your machine**: a distro, WSL, a terminal, a GPU, a font. Open an issue with what you found.

Issues labelled [`good first issue`](https://github.com/sazardev/leader/labels/good%20first%20issue) are scoped for a
first contribution; [`help wanted`](https://github.com/sazardev/leader/labels/help%20wanted) marks anything where a
second pair of hands is useful. If you want to work on something, say so in the issue so we do not duplicate it.

## Development setup

You need **Neovim 0.11+**, git and — for the desktop app — a Rust toolchain (2024 edition). `app/install.sh` installs
Rust with rustup when it is missing; the windowing and GPU libraries are loaded at runtime, so no `-dev` packages are
needed on a normal desktop.

```sh
git clone https://github.com/sazardev/leader
cd leader
git config core.hooksPath .githooks   # cheatsheet always up to date + Conventional Commits
./install.sh                          # links nvim/ as your config, installs plugins/tools/parsers
```

`./install.sh --no-plugins` only links the config; the plugins install themselves the first time you open nvim. To use a
throwaway config while developing:

```sh
XDG_CONFIG_HOME=/tmp/leader-dev ./install.sh --no-plugins
XDG_CONFIG_HOME=/tmp/leader-dev nvim
```

For the desktop app:

```sh
cd app
cargo build --release --locked
./install.sh            # installs the binary built here; --prefix DIR changes where
```

The app runs `nvim --embed` with the config above. `LEADER_FONT`, `LEADER_TIMING=1` and `WGPU_BACKEND` help when
testing rendering or startup.

## Tests

Nothing here needs network or tokens: the suites use fake backends, temp projects and a throwaway `XDG_STATE_HOME`.

```sh
./scripts/test.sh                 # everything (the same list in .github/workflows/ci.yml)
./scripts/test-session.sh         # one suite
./scripts/test-agent.sh           # agent protocol, parsers, diff, backends
./scripts/test-app.sh             # desktop app: unit tests + embed protocol (needs cargo and nvim)
cd app && cargo test --locked     # Rust only
```

When you touch the config, run the suite that owns the area plus `scripts/gen-cheatsheet.sh --check` and
`scripts/gen-docs.sh --check`. When you touch a language menu, snippet or tool, update its page in
`docs/cheatsheets/` too.

The only generated files are `CHEATSHEET.md`, `docs/docs/index.html` and `docs/offline.html`; never edit them by hand.
The pre-commit hook runs the generators and stages the result:

```sh
./scripts/gen-cheatsheet.sh       # from the real keymaps (needs the config's plugins)
./scripts/gen-docs.sh --worktree  # from the Markdown
./scripts/gen-offline.sh          # the single-file offline guide, fonts embedded
```

## Style

- **Lua**: two spaces, one file = one responsibility, the contracts at the top of each folder (`core/`, `languages/`,
  `agent/`, `panes/`…). The project uses `stylua` when it is installed; keep the surrounding style even if it is not.
- **Rust**: `cargo fmt` and `cargo clippy`. The app is `leader-nvim` (no window, no GPU, testable headless) and
  `leader-gui` (winit + wgpu); respect that direction of knowledge.
- **Shell**: POSIX `sh` where the installer runs, `bash` where it is sourced; quote paths; no bashisms in `sh` scripts.
- **Markdown**: English, short sentences, no duplicate key tables (the generated ones are the source of truth).
- **Comments** explain *why*. The code says what.

## Commits and pull requests

Commits follow **Conventional Commits** (`type(scope): subject`), validated by `.githooks/commit-msg`:

```text
feat(agent): …
fix(panes): …
docs(go): …
perf(lsp): …
test(session): …
chore(release): vX.Y.Z
```

The first line is at most 72 characters. Keep a pull request **small and focused**: one feature or fix, its tests, its
docs. A PR that does several unrelated things is hard to review and will be asked to split.

Checklist for a pull request:

- [ ] The change is described (what, why, and what a user sees).
- [ ] Tests pass locally (`scripts/test.sh` or the suites that cover the change).
- [ ] Generated files are up to date (`gen-cheatsheet`, `gen-docs`, `gen-offline`).
- [ ] Docs/cheatsheets updated when behaviour, keys or setup changed.
- [ ] No secrets, tokens, private paths or personal data.
- [ ] Screenshots or a short recording for UI changes.
- [ ] You are the author (or you disclose substantial AI assistance; you are responsible for what you send).

Maintainers review for correctness, fit with the architecture and maintenance cost. The merge is a **squash merge**;
the PR title becomes the commit. Releases are tagged from `master` (see [ROADMAP.md](ROADMAP.md)).

There is no CLA: your contribution is licensed under the project's [MIT license](LICENSE) (inbound = outbound).

## Security

Do **not** open a public issue for a vulnerability. Use GitHub's private vulnerability reporting (Security → *Report a
vulnerability*) or the contact in [SECURITY.md](SECURITY.md). We will coordinate the fix and the disclosure with you.

## Adding a language or a plugin

- A language is one file in `nvim/lua/languages/` (treesitter, LSP, Mason, formatters, linters, menu) added to `NAMES`;
  the registry feeds Mason, treesitter, conform, nvim-lint and the LSP. A language-specific menu action goes in
  `nvim/lua/languages/actions/`; a setup/test/debug adapter has its own folder under `nvim/lua/lang*`.
- A plugin is one file in `nvim/lua/plugins/<group>/` (one lazy spec per plugin). A new group is added to `GROUPS` in
  `core/lazy.lua`.
- Update the language's page in `docs/cheatsheets/` and, when you change keys, let `gen-cheatsheet.sh` write the table.

`AGENTS.md` has the contract for every folder; if a change does not fit one, open a discussion first. That is the best
way to keep the config understandable.

## Questions

If something in this guide is unclear, open a discussion with the *Contributing* label. Improving this file is a
contribution too.
