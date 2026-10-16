<!-- name: Neovim plugin (Lua) -->
<!-- desc: Neovim plugin in Lua: one module per responsibility, setup(opts), lazy loading, health, mini.test, vimdoc -->

# STACK.md: Neovim plugin (Lua)

## Summary

A Neovim plugin written in Lua for Neovim 0.10+. The public surface is `require("<name>").setup(opts)` plus user
commands and `<Plug>` mappings; everything else is split into small modules under `lua/<name>/`, one responsibility each.
Nothing heavy runs at startup: modules load on first use. Pure logic is tested headless with mini.test (or busted); the
plugin reports its state through `:checkhealth`.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Lua (LuaJIT, Neovim 0.10+) | Native to Neovim, fast |
| API | `vim.api`, `vim.fn`, `vim.uv`, `vim.system`, `vim.keymap`, `vim.treesitter` | No external runtime |
| Config | `setup(opts)` deep-merged over documented defaults, validated with `vim.validate` | |
| Types | LuaLS annotations (`---@class`, `---@param`) + `.luarc.json` | Editor checks without a build |
| Testing | mini.test (headless child Neovim) or busted + nlua | Real Neovim in tests |
| Lint/format | StyLua + luacheck (or selene) | |
| Docs | `doc/<name>.txt` vimdoc (generated from README with panvimdoc or hand-written) | `:help` works |
| Distribution | Git tags (semver) + rockspec (lazy.nvim/rocks.nvim) | |

## Project layout

```
plugin/<name>.lua               defines user commands and <Plug> maps only; requires nothing heavy
lua/<name>/
  init.lua                      setup(opts) and the public functions; thin
  config.lua                    defaults, validation, merged options
  commands.lua                  :Name subcommands → calls into modules (lazy requires)
  core/
    parser.lua                  pure logic, no vim.api (testable anywhere)
    ranking.lua
  ui/
    float.lua                   windows and buffers
    highlights.lua              default highlight groups (linked, `default = true`)
  util/
    async.lua                   vim.system / vim.uv helpers
  health.lua                    :checkhealth <name>
doc/<name>.txt
tests/
  test_parser.lua               mini.test cases
  minimal_init.lua              loads the plugin and mini.test for headless runs
.luarc.json
stylua.toml
```

Dependency direction: `plugin/ → lua/<name>/init.lua (lazy) → modules`; `core/` never touches `vim.api` or windows.

## Conventions

- `plugin/<name>.lua` only declares commands and `<Plug>` mappings; it never requires the implementation at startup.
- No default key mappings that override the user's; document suggested ones, expose `<Plug>(name-action)`.
- `setup(opts)` validates and merges options once; modules read the merged config from `config.lua`.
- Highlight groups are defined with `default = true` and linked to standard groups, so colorschemes win.
- Async work uses `vim.system`/`vim.uv` with callbacks scheduled back to the main loop (`vim.schedule`).
- Every module is a table returned at the end; no globals; annotations on every public function.
- Errors to the user via `vim.notify` with the plugin name; no `print`.

## Commands

| Task | Command |
| --- | --- |
| Test | `nvim --headless --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run()"` |
| Format | `stylua lua plugin tests` |
| Lint | `luacheck lua plugin tests` |
| Types | `lua-language-server --check .` |
| Health | `:checkhealth <name>` |
| Docs | `panvimdoc` (or edit `doc/<name>.txt`) then `:helptags doc` |

## Testing

- mini.test cases for `core/` (pure) and for commands/UI in a child Neovim (buffers, windows, extmarks asserted).
- A test that `require("<name>")` without `setup()` does not error and that startup loads nothing heavy.
- Health check tested: missing external tool is reported as a warning, not an error.

## Quality gates

- StyLua check, luacheck, LuaLS check and tests green on the minimum supported Neovim and on stable.
- `:help <name>` documents every option, command and `<Plug>` mapping.

## Dependencies

- Allowed: Neovim's own API; optional integrations (telescope, plenary) loaded with `pcall(require, ...)` and documented.
- Do NOT use: hard dependencies on other plugins for core features, global variables, `vim.cmd` strings where a Lua API
  exists, synchronous `vim.fn.system` for long commands, default mappings that clobber user keys.

## Rules for agents

- Keep `plugin/<name>.lua` to commands and `<Plug>` maps; require modules lazily inside them.
- Put each responsibility in its own module under `lua/<name>/`; keep `core/` free of `vim.api`.
- Validate options in `config.lua` with `vim.validate` and document every option in vimdoc.
- Annotate public functions with LuaLS types.
- Define highlights with `default = true` links.
- Use `vim.system`/`vim.uv` for external commands and schedule results back with `vim.schedule`.
- Never add default keymaps; expose `<Plug>` mappings.
- Add a mini.test case for every new function in `core/` and every new command.
- Update `health.lua` when adding an external dependency.
