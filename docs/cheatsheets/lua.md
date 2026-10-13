# Lua (the config itself)

Filetype: `lua`.

## Tools

| What | With |
|---|---|
| LSP | `lua_ls` (NvChad enables it) |
| Format (on save and `<leader>fm`) | `stylua` (always installed, also in light mode) |
| Treesitter | `lua`, `vim`, `vimdoc` |
| Extra | **lazydev**: Neovim API types and completion of `require()` / plugin modules |

## Completion

In Lua the blink sources are: `lazydev`, LSP, path, snippets, buffer (lazydev with priority).

## Useful commands

| Command | Action |
|---|---|
| `:luafile %` | run the current file |
| `:lua =expr` | evaluate and print an expression |
| `:Lazy sync` | install/update plugins (the `git pull` auto-reload does not do it) |

## Auto-reload

After `git pull`, the `.githooks/post-merge` hook leaves a marker and, when nvim opens (`UIEnter`),
`core/autocmds/reload.lua` runs `luafile $MYVIMRC`. Enable it once per clone:

```sh
git config core.hooksPath .githooks
```

It reloads Lua, but does **not** install/remove plugins or treesitter parsers.
