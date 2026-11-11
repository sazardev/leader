# Roadmap

This is a direction, not a promise. Items move when someone has the time, the tests pass and the result fits Leader's
opinions. Comment on an issue or open a discussion to push something up the list; the labels `help wanted` and
`good first issue` mark where a contribution is welcome.

## Now

- **1.18 stability**: sessions, panes, local FIM completion and the installer. Reproduce, report, fix.
- **Community base**: issue/PR templates, contributing and security docs, CI, the repo polish (this document included).
- **Signed releases again**: restore the `Leader Releases` key and sign every asset from 1.19 on; the 1.15–1.18 assets
  are checksummed but unsigned. The installer already verifies signatures when they exist.
- **Docs**: keep the generated cheatsheet, the single-page documentation and the offline guide in sync; one page per
  language, one contract per folder.

## Next

- **Desktop app on macOS and Windows** (the config already runs in a terminal; the app is Linux + WSL today).
- **IME composition** for CJK and other input methods (dead keys and AltGr already work; the remaining edge cases are
  documented in `AGENTS.md`).
- **Ligatures and font features** in the GPU renderer.
- **Smooth scrolling** and native cmdline/popupmenu/messages (`ext_*` UIs) instead of the current fallbacks.
- **More language packs** (Ruby, PHP, Elixir, Zig…): one file in `nvim/lua/languages/`, its menu, its cheatsheet page and
  its tests.
- **Agent evaluation** on real projects, more local-model presets, and a cheaper “light” path for docs and explains.
- **Accessibility**: keyboard-only flows, screen-reader friendliness where the terminal allows it, contrast in every
  theme derived from the terminal.

## Later / exploring

- A small **extension API** for actions, presenters and providers, so a language pack can ship its own without forking
  the flow.
- **Opt-in, local-first settings sync** across machines (no account, no telemetry).
- A **marketplace** for skills, recipes and SPEC modules (the existing catalogs already have the shape).
- More **single-file offline guides**: the whole documentation, wallpapers and the cheat sheet in one downloadable
  artifact.

## Explicitly not planned

- A fork of Neovim. Leader is a config plus a front-end; the editor stays Neovim.
- A subscription, telemetry or a cloud account. The agent uses the backend you choose; local-first is the default.
- A plugin manager of its own. `lazy.nvim` does that well.

## How to help

Pick an item, open an issue saying you are on it, and read [CONTRIBUTING.md](CONTRIBUTING.md). A failing test and a
small pull request beat a long design document; if the design is the hard part, start a discussion.
