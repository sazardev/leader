# GitHub (`<leader>Gh`)

A global menu for the `gh` CLI: the TUIs that visualize your work and octo.nvim for editing PRs and issues without
leaving Neovim. It is global on purpose (gh-dash and the notifications are about your account, not the folder); the
actions that need a repository say so. The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md).

## TUIs (`gh` extensions)

| Key | Extension | What it shows |
|---|---|---|
| `d` | [gh-dash](https://github.com/dlvhdr/gh-dash) | PRs and issues in one dashboard: Vim keys, preview, comments, merge |
| `o` | [gh-observer](https://github.com/fini-net/gh-observer) | the checks of the current PR, live, with queue and run times |
| `e` | [gh-enhance](https://github.com/dlvhdr/gh-enhance) | Actions runs, jobs and logs; rerun the failed ones |
| `n` | [gh-news](https://github.com/chmouel/gh-news) | notifications as a TUI (read, mute, snooze, open) |

Each one lives in **its own terminal** (`utils/terminal.tui`): pressing the key again while it runs only brings it
back to the front (the command is never typed into the TUI); `Esc` closes the window and the TUI keeps running in
the background. Reopening is instant. They are Nerd Font TUIs: the icons need a patched font in the terminal.

The first time, if the extension is not installed, Leader shows the exact `gh extension install …` line and, after
you confirm, installs and launches it in one step. `<leader>Ghs` opens the checklist of every extension in the menu
(missing ones checked, installed ones listed): `Enter` installs the checked ones in the shared terminal; nothing
runs before that. By hand:

```sh
gh extension install dlvhdr/gh-dash
gh extension install fini-net/gh-observer
gh extension install dlvhdr/gh-enhance
gh extension install chmouel/gh-news
```

Configuration lives where each tool expects it: gh-dash reads `~/.config/gh-dash/config.yml` (and a repo-level
`.gh-dash.yml`); gh-observer auto-detects the PR of the current branch.

## octo.nvim (PRs and issues inside Neovim)

`p` lists PRs, `i` issues and `r` starts a review of the current branch's PR. The plugin
([octo.nvim](https://github.com/pwntester/octo.nvim)) is lazy-loaded on `:Octo` and uses Telescope (the picker this
config already has). Inside an Octo buffer its own keys apply: `<CR>` lists the actions, `<localleader>` has comments,
labels, reviewers and reactions, and a review opens a tab with the changed files and their diff. Projects v2 needs
the `read:project` scope (`gh auth refresh -s read:project`).

## Core `gh` commands

| Key | What it does |
|---|---|
| `v` | open the current PR in the browser |
| `c` | checks of the current PR (plain table) |
| `b` | open the repository in the browser |
| `a` / `A` | `gh auth status` / `gh auth login` |

These run in the shared command terminal, so errors (no PR for the branch, no remote, credentials) stay readable;
`Esc` closes the window without stopping anything.

## Pitfalls

- Everything needs `gh` installed and logged in: `A` runs `gh auth login` in the terminal.
- `gh observer` and `gh enhance` need a PR/branch with Actions; gh-dash and gh-news work from any folder.
- octo.nvim is installed by lazy on the next start after pulling this config (or `:Lazy sync`); until then the menu
  says so.
