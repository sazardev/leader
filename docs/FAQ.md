# FAQ

Short answers to the questions that come up most often. The long version is in the [documentation](https://leader.sazardev.stream/docs/)
or in [`CHEATSHEET.md`](../CHEATSHEET.md); the offline copy of the whole guide is [the single-file guide](https://leader.sazardev.stream/offline)
(also `docs/offline.html` in the repository).

### Is Leader a fork of Neovim?

No. Leader is two things: a **Neovim config** (the `nvim/` folder, Lua, plugins, menus) and a **desktop front-end** (the
`leader` binary, Rust + wgpu) that runs `nvim --embed` and draws the UI in its own window. The editor is stock Neovim,
with your normal `:commands`, LSP servers and plugins.

### Do I need the desktop app?

No. The config works in any terminal (Linux, macOS, Windows) and in the app. The app adds menus, a command palette,
projects with their sessions, a toolbar, the terminal-inherited theme and a GPU-rendered grid.

### Which platforms are supported?

| | Config (terminal) | Desktop app |
|---|---|---|
| Linux x86_64 | ✅ | ✅ (Wayland, X11, WSLg) |
| Linux aarch64 | ✅ | build from source |
| macOS | ✅ | ❌ (planned) |
| Windows | ✅ PowerShell / WSL | WSL only (native Windows planned) |

The one-liner installs the app on Linux x86_64 and the config everywhere else.

### What does the installer change on my machine?

It installs `~/.local/bin/leader`, a menu entry, the docs/man pages, Neovim (if missing or too old), the config in
`~/.config/nvim`, plugins, language tools and parsers. An existing Neovim config is moved to `nvim.bak-<date>`, never
deleted. Re-running it is idempotent. `--dry-run` shows the plan; `--no-config` installs only the app.

### How do I update?

Re-run the one-liner. It brings the app, the config, the plugins and the tools to the current versions. If you cloned the
repo, `git pull && ./install.sh`; for plugins only, `:Lazy sync`. The **Settings** menu also has **Check for Updates**
and **What's New**.

### How do I uninstall?

```sh
curl -fsSL https://leader.sazardev.stream/install | bash -s -- --uninstall
```

This removes the app, its menu entry and its manual pages. The config and your files stay. To remove everything, delete
`~/.config/nvim`, `~/.local/share/leader` and `~/.local/state/nvim` (back up `lua/local.lua` first if you customized it).

### Will it overwrite my current Neovim config?

It moves it to `~/.config/nvim.bak-<date>` and links Leader in its place. You can restore the backup at any time. To try
Leader without touching your config, install into a throwaway `XDG_CONFIG_HOME`.

### Why are there so many plugins and languages?

Everything is lazy: a plugin loads on an event, a filetype or a key, and a language only installs its LSP, formatters and
linters if you keep its pack. `--lang` (or `<Space>Sp` → **Languages**) leaves out what you do not use. On a machine
with ≤ 2 GB of RAM, **light mode** turns off the resident LSP servers and keeps the editor usable.

### Does Leader phone home?

No telemetry, no analytics and no account. The config sends nothing on its own. The only network calls are the ones you
trigger: the plugin/tool installer, an agent request, the optional update check (raw GitHub files, no API key) and a
language server downloading its runtime. The website uses no cookies.

### Which AI backends does the agent use?

Any of these, chosen in `<leader>am`:

- **Claude Code** (`claude`), **OpenCode** (`opencode`), or any CLI you declare in `agent.custom`;
- **Ollama** and **LM Studio / llama.cpp / vLLM** through their OpenAI-compatible HTTP APIs;
- a local **FIM** completion (Qwen2.5-Coder 1.5B via llama.cpp), off by default and toggled with `<leader>SF`.

The agent is one-shot by default (implement, review, explain, fix…), with a persistent chat under `<leader>aC`.

### Does the agent see my code and secrets?

It sends the target and the context Leader builds (types, diagnostics, project rules, selected files) to **the backend
you chose**. A local backend stays local; a cloud backend receives that context. The AI commit draft excludes common
secret files (`git.commit.sensitive`: `.env`, keys…) and the agent does not read outside the project. If the repository
contains a secret, treat it as readable by the model you selected; use a local model for sensitive code.

### Where are my settings, sessions and history?

- `~/.config/nvim/lua/local.lua`: per-machine settings (theme, languages, FIM, clipboard…), git-ignored.
- `stdpath("state")`: sessions, recent files, agent history and spend, the agent choice, the settings you changed in the
  panel, the terminal theme marker, the task and project caches.
- `~/.local/share/leader`: the cloned config and its docs (if you used the installer).

Back up `local.lua` and `~/.local/state/nvim` to keep your setup; the rest is regenerated.

### How do I learn the keys?

Press `<Space>` and read the menu; it only shows what applies to the current buffer. The dashboard's **Mappings** button
opens the whole cheat sheet, and [`CHEATSHEET.md`](../CHEATSHEET.md) is the same file (generated from the real keymaps).
`<Space>Sp` is the settings panel. The [documentation](https://leader.sazardev.stream/docs/) has a page per language and
per feature, and the [offline copy](offline.html) works without network.

### Can I use it offline?

Yes. [The offline guide](https://leader.sazardev.stream/offline) is a single file with the whole guide, the CSS and the
fonts embedded; the repository also has it as `docs/offline.html`, so it travels with a clone. Download it and open it
in any browser. The editor itself is local; only plugin/tool installation, agent requests and update checks need the
network.

### A plugin update broke something. How do I roll back?

The plugins are pinned in `nvim/lazy-lock.json`. `:Lazy restore` returns to the pinned versions; if you updated the
lockfile, `git checkout nvim/lazy-lock.json` (or `git revert`) and `:Lazy restore` again. The same file is committed so a
release is reproducible.

### Is Leader free?

Yes. MIT license, no paid tier, no CLA. If it saves you time, the best ways to give back are a bug report, a docs fix, a
patch or a star on the repository.

### How do I contribute?

Read [CONTRIBUTING.md](../CONTRIBUTING.md), pick an issue labelled `good first issue` or `help wanted`, or open a
discussion. There is no CLA; contributions are MIT, inbound = outbound.

### Why is it called Leader?

The whole config hangs off one key: the leader key (`<Space>`). "Leader" is also the binary: the editor that leads your
project, not a plugin you have to assemble.
