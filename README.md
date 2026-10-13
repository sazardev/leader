# my-nvim-setup

A **Neovim** config on top of NvChad v2.5, designed as a small **framework**: you clone it, run a script and get an
editor ready to work, with what a developer uses every day and nothing more. Minimalism, fast productivity and
performance: everything loads lazily, one file = one responsibility, and whatever you don't use is turned off with one line.

`v1.0.0` · Neovim ≥ 0.11 · Linux, WSL, macOS and Windows

## Installation

**One command, everything done** (Linux, WSL, macOS):

```sh
curl -fsSL https://raw.githubusercontent.com/sazardev/my-nvim-setup/master/install.sh | bash
```

Windows (PowerShell): `irm https://raw.githubusercontent.com/sazardev/my-nvim-setup/master/install.ps1 | iex`

It needs nothing from you: no clone, no prompts. It fetches the repo into `~/.local/share/my-nvim-setup` and does everything
(idempotent: run it again any time to bring it up to date):

1. installs whatever is missing from the system (git, curl, C compiler, ripgrep, node, cmake) and **Neovim ≥ 0.11** if you don't have it
   (in `~/.local/opt`, without `sudo`; with brew on macOS);
2. links `nvim/` as your config (`~/.config/nvim`); an existing one is moved to `nvim.bak-<date>`, never deleted;
3. enables the git hooks (`.githooks`: cheatsheet always up to date and conventional commits);
4. writes your **per-machine settings** (`nvim/lua/local.lua`, git-ignored) if you pass the options below;
5. installs the plugins at the versions pinned in `nvim/lazy-lock.json` (in parallel), the LSPs/formatters/linters (Mason) and builds the
   treesitter parsers (`tree-sitter-cli` comes from Mason), reporting the time each step took;
6. **sets up the AI agent** with the best backend it finds (Claude Code, OpenCode, Ollama…); `--agent none` skips it.

Options go after `bash -s --`, for example a Go laptop, fully configured:

```sh
curl -fsSL https://raw.githubusercontent.com/sazardev/my-nvim-setup/master/install.sh | bash -s -- --lang go,lua --theme gruvbox
```

Prefer to clone it yourself (to hack on it)? `git clone https://github.com/sazardev/my-nvim-setup && cd my-nvim-setup && ./install.sh` does exactly
the same. Override the fetch with `NVIM_CONFIG_DIR`, `NVIM_CONFIG_REPO` and `NVIM_CONFIG_BRANCH`.

Then open `nvim`. Press `<Space>` and which-key shows you the menus.

| Option | Effect |
|---|---|
| `--ask` | prompts before installing system packages or Neovim (by default it asks nothing) |
| `--lang go,typescript` | only those languages (+ lua): the rest are disabled in `local.lua`, so nothing you don't use gets installed |
| `--theme catppuccin` | default theme (`local.lua`) |
| `--light` / `--no-light` | forces light mode (no resident LSP) or turns it off; without this it is detected by RAM (≤ 2 GB) |
| `--agent auto` | the AI agent (`auto` is the default and picks the best available), `claude/haiku`, `ollama/qwen2.5-coder:7b@light`…; `none` skips it |
| `--no-deps` | doesn't touch system packages or Neovim |
| `--no-plugins` | only links; plugins and tools install themselves the first time you open nvim |
| `--dry-run` | shows what it would do |

```sh
./install.sh --lang go,lua --theme gruvbox --agent claude/haiku   # from a clone: a Go laptop, everything configured
./install.sh --dry-run --no-deps --lang rust                      # see what it would do
```

Available languages: `lua go typescript html css tailwind json yaml toml markdown docker prisma astro dart rust python java kotlin yarnspinner`.
If `local.lua` already exists it is **left untouched**: the installer tells you what to add (it is yours and may hold other settings).

**Native Windows** (PowerShell): `./install.ps1 [-Lang go,typescript] [-Theme x] [-Light|-NoLight] [-Agent auto] [-NoPlugins]` creates the
junction at `%LOCALAPPDATA%\nvim` and does the same steps (written but not tested on real Windows; on WSL use `install.sh`).

**Uninstall**: delete the `~/.config/nvim` link (and, if you want, `~/.local/share/nvim`, `~/.local/state/nvim`, `~/.cache/nvim`).

## Philosophy

- **Fast**: ~20 ms startup (measured headless, with `--startuptime`); `defaults.lazy = true`, plugins loaded by event/filetype/command/key, bytecode cache (`vim.loader`) and unneeded built-in plugins disabled.
- **Minimal**: 54 entries in `lazy-lock.json`, **counting** dependencies and NvChad's own. No heavy session manager, no tab bar, no embedded AI chat, no LSP dependency tree for things you don't use.
- **Modular**: the config is *declared*, not wired. Adding a language, a plugin, an agent action or a Go helper means creating one file; nothing else is touched.
- **Spend the minimum**: whatever can be decided without a model is decided beforehand (gates, local analysis, treesitter completion); when one has to be called, only what is needed is sent and the cost is shown.
- **Light where it matters**: with ≤ 2 GB of RAM the resident processes (LSP, golangci-lint) are turned off automatically; force it with `NVIM_LIGHT=1|0`.
- **Everything by keyboard**, with keys documented and generated from the real code.

## What's included

| Area | Contents |
|---|---|
| Languages | Go, TypeScript/JS/TSX, HTML/CSS/Tailwind/Astro, Python, Rust, Dart/Flutter, Java/Kotlin, Lua, Markdown, JSON/YAML/TOML, Docker, Prisma, YarnSpinner. Each one declares its LSP, formatter, linter, parsers and its `<leader>` menu (it only exists in buffers of that filetype) |
| Editing | blink.cmp, mini.pairs/surround/move, multicursor, flash (jumps), treesitter textobjects, folds (ufo) with foldable long comments, custom snippets |
| Navigation | Telescope (+fzf), nvim-tree, harpoon, aerial (symbols), grug-far (global replace), file history |
| Git | gitsigns, diffview, git-conflict, git-blame (off by default) and **conventional commits** (see below) |
| Diagnostics | inline blocks under their line, line number colored by severity, unique colors across the whole UI, line popup, Trouble |
| UI | lualine, gruvbox ↔ light theme **or live-inherited from the terminal** (Alacritty), dashboard with braille art, render-markdown, inline colors |
| Sessions | one per folder and branch, periodic autosave |
| **Go without an LLM** | completion helpers that read your code and your `go.mod` (see below) |
| **AI agent** (optional) | `<leader>a`: one-shot actions on the function under the cursor, with an inline diff (see below) |

### Commits (`<leader>G`)

A **single panel** for committing: what goes in (staged vs not staged, with +/− per file), the message with **live Conventional Commits
validation** (`✔ feat(scope) · 38/72`), assisted type and scope, and a line saying what the agent will do *before* spending anything.
`Gc` opens the panel, `Gm` opens it with the AI draft, **`GM` commits on its own, in the background** (stages what is modified except sensitive files,
the AI writes ONE message in English, it is validated and committed; if anything fails, it undoes what it staged) and `Ga` rewrites the last one. The
AI message is always in English, on one line, in ~2 s with a light model.

### AI agent (`<leader>a`)

It is not a plugin: it is Lua code in this config, with no dependencies, and it does nothing until you invoke it. Claude Code, OpenCode, **Ollama (CPU/CUDA)**,
LM Studio/llama.cpp/vLLM and other CLIs; it detects and configures its backends on its own (`<leader>am` → Setup, or `./scripts/agent-setup.sh`).
A short generic menu and one menu per **level**, each with its own folder and actions:

| Menu | What it does |
|---|---|
| `<leader>a` | implement, review, explain, ask, document, refactor, hand off to Herdr; **`f` inline fix** (the line's diagnostic, with the type of what it points at) and **`F` block fix** (the whole function) |
| `aT` **tests** | `w` writes only the missing tests at the end of the test file · `m` mock · `f` fixes a test by running it first (if it already passes, 0 tokens) · `g` gaps (local) |
| `aL` **lenses** | security, performance, concurrency, errors, API compatibility: single-focus reviews as diagnostics; each one first discards what is not its concern |
| `aD` / `aP` / `aS` | hexagonal architecture: domain, repositories and services, with local 0-token analysis |

Also: clear findings one at a time, per file or all of them (`<leader>ac`, `aC`, `:AgentClear`), history with prompt, response, tokens and cost
(`<leader>ah`), models per tier (cheap where it is enough). Details in [docs/cheatsheets/agent.md](docs/cheatsheets/agent.md).

### Go without an LLM (smart completion, 0 tokens)

On top of a shared index (`utils/goindex.lua`: treesitter + `go.mod`, cached by date):

- **missing methods** to satisfy an interface, with the exact signature and bodies that call your dependency (`return s.repo.FindByID(ctx, id)`);
- **`if err != nil`** with the zero values of the function's returns and a message taken from what is called (the menu opens by itself after `x, err := …`);
- **mappers** between layers (`NoteResponse` ↔ `Note`), **constructor wiring** (`NewNoteService(noteRepo)` with the arguments resolved),
  **enum helpers** (`IsValid`, `Parse`, `UnmarshalText`…), **interface from a struct** and `var _ I = (*T)(nil)`,
  **HTTP handlers** from a service (net/http, chi, gin, echo);
- struct tags, constructors, filled literals, sentinel errors, statement snippets. Details in [docs/cheatsheets/go.md](docs/cheatsheets/go.md).

## Customizing

Everything configurable is in `nvim/lua/core/settings.lua` with its default value and a comment. Your changes go in
`nvim/lua/local.lua` (git-ignored, merged on top; the installer can generate it with `--lang`, `--theme`, `--light`):

```lua
-- nvim/lua/local.lua
return {
  theme = { name = "catppuccin" },
  languages = { disabled = { "astro", "dart", "java", "kotlin" } },
  agent = { backend = "ollama", tiers = { lens_security = "light" } },
  git = { commit = { subject_max = 60 } },
}
```

To add (each one is **a single file** and, at most, a name in its `NAMES` list):

- **a language**: `nvim/lua/languages/<name>.lua` (contract at the top of `languages/init.lua`);
- **a plugin**: a file in `nvim/lua/plugins/<group>/`;
- **a dashboard art**: `nvim/lua/ui/arts/<name>.lua` (braille only);
- **an AI backend**: an entry in `agent.custom` (no code) or `nvim/lua/agent/backends/<name>.lua`;
- **an agent action, lens or test**: `agent/actions/`, `agent/lenses/actions/` or `agent/tests/actions/`;
- **a per-language test convention**: `agent/tests/convention.lua`;
- **a Go completion helper**: a `utils/go<name>.lua` module on top of `goindex` and its call in `gosmart`.

## How it is organized

The principles (the same across the whole repo) and where they show:

- **One responsibility per module**: the pure parts (`commit/conventional.lua`, `utils/goindex.lua`, `agent/protocol.lua`) kept apart from what touches
  git, the LSP or the UI (`commit/git.lua`, `commit/panel.lua`); one presenter per output kind (`agent/output/`).
- **Open for extension, closed for modification**: discovered registries (`languages/`, `agent/actions/`, `agent/backends/`, `agent/lenses/`);
  adding one doesn't force editing the others. The agent pipeline is extended with action hooks (`retarget`, `merge`, `reveal`, `prepare`).
- **Dependencies point to abstractions**: each piece talks to a small contract (a backend's `build`/`parser`, a context provider's `collect(target, done)`,
  a Go helper's `declaration_items(range, frag)`), not to its neighbor's implementation.
- **Configurable things in a single place**: `core/settings.lua`; the scripts (`install.sh`, `install.ps1`) share the same settings logic
  (`scripts/install-local.lua`) instead of duplicating it.

## Keys and documentation

- [`CHEATSHEET.md`](CHEATSHEET.md): **all** the keys. It is generated from the real keymaps (`scripts/gen-cheatsheet.sh`; the pre-commit hook regenerates it). Inside nvim, the dashboard's *Mappings* button shows the same.
- [`docs/cheatsheets/`](docs/cheatsheets/README.md): what the code doesn't say (workflows, tools, pitfalls), one page per language and the agent's.
- [`AGENTS.md`](AGENTS.md) / [`CLAUDE.md`](CLAUDE.md): architecture and pitfalls for whoever touches the config (people or agents).

## Structure

```
install.sh · install.ps1      installation (Linux/WSL/macOS · Windows)
VERSION                       config version
nvim/                         the config (what gets linked)
  init.lua                    bootstrap only
  lua/core/                   settings, options, keymaps and startup autocmds
  lua/languages/              one file per language (declared; not wired)
  lua/plugins/<group>/        one lazy spec per plugin
  lua/menus/                  contextual leader menus
  lua/agent/                  AI agent: backends, actions, context, output, tests, lenses, ddd, setup
  lua/commit/                 commits: validation (pure), git, AI draft, panel
  lua/utils/                  utilities; go*.lua = Go completion helpers on top of goindex
  lua/ui/ appearance/ themes/ dashboard, theme, colors
  snippets/ ftdetect/ syntax/ custom snippets and filetypes
scripts/                      installation (install-*.lua), cheatsheet, agent setup and tests
docs/cheatsheets/             per-language and agent documentation
.githooks/                    up-to-date cheatsheet + Conventional Commits
```

## Maintenance

- Update: re-run the install command (or `git pull && ./install.sh`): it brings the plugins to the versions pinned in `lazy-lock.json`; the config reloads itself when nvim opens.
- Check: `scripts/test.sh` runs everything (agent and commits, Go helpers, installer and up-to-date cheatsheet; no network or tokens); each
  suite can also be run on its own: `scripts/test-agent.sh`, `scripts/test-go.sh`, `scripts/test-install.sh`, `scripts/gen-cheatsheet.sh --check`.
- Commits: Conventional Commits format (`feat(scope): subject`); the `commit-msg` hook validates it and `<leader>Gc` / `Gm` / `GM` assist with it.
