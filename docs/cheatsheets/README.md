# Cheatsheets

> **Keys: [`CHEATSHEET.md`](../../CHEATSHEET.md)** (repo root) — the **only** source.
> It is **generated** by reading the real keymaps (`scripts/gen-cheatsheet.sh`) and regenerated on every commit;
> it is not edited by hand and its tables are not duplicated here. Inside nvim, the dashboard's **Mappings** button
> (`NvCheatsheet`) shows the same thing live.
>
> These pages hold **what the code doesn't say**: what each thing does, workflows, tools, pitfalls.
> `<leader>` = `Space`.

| Cheatsheet | What it covers |
|---|---|
| [go.md](go.md) | **Go in depth**: struct tags, snippets, contextual completion, `<leader>g` menu |
| [agent.md](agent.md) | **Inline agent** (`<leader>a`): one-shot implement/review/explain... with Claude or OpenCode |
| [tasks.md](tasks.md) | **Makefile tasks** (`<leader>R`): the picker, writing targets it can list, the preset Makefiles per language |
| [typescript.md](typescript.md) | TypeScript / JavaScript / TSX |
| [python.md](python.md) | Python |
| [rust.md](rust.md) | Rust |
| [dart-flutter.md](dart-flutter.md) | Dart / Flutter |
| [java-kotlin.md](java-kotlin.md) | Java and Kotlin (Gradle / Maven) |
| [lua.md](lua.md) | Lua (the config itself) |
| [markdown.md](markdown.md) | Markdown |
| [web.md](web.md) | HTML, CSS, Tailwind, Astro |
| [data-formats.md](data-formats.md) | JSON, YAML, TOML, Docker, Prisma, YarnSpinner |

## How the leader works

Each language has **its own letter** under `<leader>` and **only exists in buffers of that filetype**;
`<leader>G` (Git) only inside a repo, and `<leader>P` (sessions), `<leader>S` (settings), `<leader>F` (files) and `<leader>C` (comments) are global.
Press `<leader>` and which-key shows only what applies to the current file (no delay).

The language menus open an integrated terminal (toggleterm) and run the commands at the **project root**
(they detect `go.mod`, `package.json`, `Cargo.toml`, `pubspec.yaml`, `pom.xml`/`build.gradle`...).

## Workflows worth knowing

The exact keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md); here, how they combine.

- **Jump and come back**: after `gd` / `grr` / `Ctrl+click`, `Esc` returns to where you were (if you didn't edit there); it also closes popups and clears the highlight. `Ctrl+o` / `Ctrl+i` walk the jump history.
- **Line diagnostic** (`<leader>xd`): opens a popup; press it again to enter it and copy the text.
- **Diagnostic blocks** (`utils/diagblocks.lua`): `<leader>xa` draws all of them under their line (a bar in the severity color, source/code and a `2/5` counter); `<leader>xc` toggles between all expanded and one by one (each one a single line, only the one on the cursor line opens); `<leader>xn`/`xp` jump to the next/previous and turn the view on in one-by-one mode. They show up on their own in every buffer with diagnostics (the text on the right, `virtual_text`, is off) and `<leader>xa` turns them off in that buffer; then only the tinted line number remains. In insert mode the blocks are hidden (nothing appears or pushes the code while you type) and come back when you leave with `Esc`; `diagnostics.update_in_insert = true` keeps them live. **Matched colors** (`ui/diagcolors.lua`): the `E2`/`W1` label in the status bar, the line number and each block's label are the SAME pill (background = the theme's `DiagnosticError/Warn/Info/Hint`, text = the theme background, bold), and the block's side bar uses that same accent; this way they change together with the theme (also with the theme inherited from the terminal and when Alacritty changes live: `diagcolors.sync()` detects the change on every status bar refresh and recomputes number and blocks, because base46 loads its cache without notifying through an event). **Gutter**: no icons either on the left or next to the code. The line number is drawn with the pill of the highest severity on the line (red error, yellow warning, blue info, cyan hint); the pill fits the digits, with a space on each side, so the number ends up centered (it is drawn by `'statuscolumn'`, defined in `settings.options`, and lines split by `wrap` only leave the gap) and git is a thin `┃` bar attached to the number (`signcolumn=no`: the statuscolumn draws the sign in ONE cell; with `signcolumn=yes` each sign takes two and an extra gap is left) (green added, blue changed, red deleted), so they are not confused. Your choice (`<leader>xa` on/off, `<leader>xc` expanded/collapsed) is global and saved in `stdpath("state")/diagblocks.json`, so it comes back the same when you reopen nvim; `settings.diagnostic_blocks` (`auto`, `mode`, `number`) only gives the initial value. `<leader>xn`/`xp` with the view off turn it on only in that buffer and don't touch what is saved. It updates on its own when diagnostics or the cursor change. The bottom panel (`<leader>xx`, Trouble) opens with focus: `Enter` jumps to the diagnostic and opens its popup, like `<leader>xd`.
- **Delete without clobbering the clipboard**: `<leader>d` + motion (`<leader>dd` line, `<leader>dw` word) or in visual mode.
- **Multicursor** (`multicursor.nvim`, real cursors like VS Code/Helix; loaded on the first key): add cursors by line (`Ctrl+↑/↓`), by match of the word or selection (`Alt+n`/`Alt+p`, `Alt+Shift+n/p` skips one) or all at once (`Alt+a`); `Alt+click` adds or removes one with the mouse. With several cursors everything (motions, operators, insert, undo) is repeated on each one; `Esc` clears them, `Ctrl+q` turns the main cursor off/on, `←/→` switch cursor and `Alt+x` deletes the current one. In insert mode, the secondary cursors replicate what was typed ON LEAVING insert; if the completion menu is open, `Esc`/`jk` close it first and you have to press them again. Ideas: `Alt+a` on a word to rename it in the file; `Ctrl+↓` several times + `I`/`A` to edit columns. The **native visual block** (`Ctrl+v` + `I`/`A`/`c`) is still there for simple columns. Don't use `Ctrl+n` (it is nvim-tree).
- **Textobjects** (treesitter): combine them with operators — `daf` deletes the function, `dif` the body, `cif` changes it, `yaf` copies it, `vaf` selects it; `dac` deletes the class. For braces of any block: `di{` (inside), `da{` (with braces), `%` jumps to the pair. **PageDown/PageUp** jump block by block (function, method, class, struct/interface in Go); they don't stop at closures inside a function, accept a count (`3<PageDown>`) and, with no blocks or no parser, do the normal scroll. **Home/End** go to the start/end of the current block; pressing them again goes up to the enclosing block (method → class → file). For start/end of line use `^`/`$` (or `0`), and in insert they remain native.
- **Alt+hjkl** move a line or block (mini.move); in Normal mode `Alt+h` is NvChad's horizontal terminal instead (the visual block still moves left).
- **Format**: `<leader>fm` formats (conform); it also formats on save.
- **Telescope**: the preview is always visible. `flex` layout: on the right in windows ≥ 110 columns, at the bottom in narrow ones (`lua/plugins/navigation/telescope.lua`).
- **nvim-tree**: opening a file closes the tree; `I` shows/hides what git ignores. Deleting a folder warns how many files it contains.
- **Terminal**: `Alt+i` (float), `Alt+v` (vertical) and `Alt+h` (horizontal) open NvChad's terminals, `<leader>g…` the toggleterm one. `Esc` (Terminal or its Normal mode) closes the window and the shell keeps running; `Shift+Esc` only hands the focus back to the previous window and leaves the terminal open. `Shift+Esc` needs a terminal that tells it apart from `Esc`; if yours doesn't, it behaves like `Esc`.
- **Completion** (blink.cmp): the documentation appears **instantly** on selection and, for snippets, shows **what will be inserted**. Nothing comes preselected, except inside a Go struct tag (there `Enter` accepts the first suggestion). Sources: LSP, path, snippets, buffer; in Go `gotags` and `gosmart` are added; in Lua, `lazydev`.
  - **With the menu open**, `Tab` / `Shift+Tab` pick a suggestion (and `Enter` inserts it). **Without a menu**, inside a snippet (e.g. `gorm.Open(dialector, opts)`), they jump to the next / previous placeholder.
  - **Keep what you typed and move on**: `Esc` (closes the menu without leaving the snippet) and then `Tab`.
  - **`Esc` (or `jk`) with the menu open only closes it** and undoes the suggestion that was inserted (back to what you typed); you stay in insert mode and in your snippet. Without a menu, they leave insert as usual.
- **Sessions**: one per folder (and per git branch; `main`/`master` use the base). They are not restored automatically: **Restore Session** button (`rs`) on the dashboard or its menu key. Opening a single file (`nvim x`) and quitting overwrites that folder's session; there is a key to not save on exit.
- **Git**: git-blame is off by default (no cost); it is toggled from the Git menu.
- **Conventional commits** (`<leader>G`, a single panel): `Gc` opens the panel, `Gm` opens it and immediately asks the AI for the draft, `GM` commits **on its own, without a panel** (see below), `Ga` rewrites the last commit (warns if it is already on the remote). At the top you see **what gets committed**: what is staged (`●`, with +/− per file) and, separately, what does **not** go in (`○`, modified or new); `Space` stages/unstages the file (or the whole group if you are on its header), `a` stages everything, `u` unstages everything, `p` or `Enter` show its diff. Below you write the message and the title is **validated live** (`✔ feat(scope) · 38/72`, or why it fails); `Ctrl+t` picks the type (suggested from the files) and `Ctrl+o` the scope (from the paths and the history). Underneath, a line says what the agent will do **before spending anything** (`✦ AI claude/haiku · ⌃g to draft · reads 2 files, 3.1k chars`: light model, only reads what is staged: its compact diff without lockfiles capped at `git.commit.diff_max_chars`, the branch and the list of types) and, when done, what it did (`drafted by … · 2.5s · 1.2k→39 tok · $0.0001`); `Ctrl+g` asks for the draft (never on its own, except with `Gm`), replaces the message and is undone with `u`, and repeating it gives another one. The message is **always in English and on a single line** (Conventional header; ~2 s with haiku). **`GM` automatic commit**: no panel and in the background; if you already staged files it commits only those, otherwise it stages everything modified except sensitive files (`git.commit.sensitive`: `.env`, keys…), the AI writes the message, it is validated and committed, and a one-line notice gives hash, message, files, +/−, time and cost. If something fails (no backend, AI, invalid header, a hook) it undoes what it staged and leaves nothing half done (`Gm` to do it by hand). `Ctrl+s` (or `Enter` in normal mode) commits; with nothing staged or with an invalid message it warns and does nothing; if a hook rejects the commit the panel stays open so you can fix it. `Tab` toggles files ↔ message, `q`/`Esc` cancel (and stop the agent). The `.githooks/commit-msg` hook requires the same format on any `git commit` (types and length in `git.commit`; if you change the list of types, change it in the hook too).
- **Comments** (`<leader>C`): `Cd` inserts the idiomatic documentation template for the function/type under the cursor (godoc, LuaCATS, JSDoc, docstring, rustdoc) with name, parameters and return already filled in; `Cm` lists in quickfix the public items that have no doc comment (for other languages use the agent: `<leader>ad`). Snippets in any language, with the language's own comment style: `todo`, `fixme`, `note`, `hack`, `warn`, `perf`, `deprecated` (and with `o` at the end, e.g. `todoo`, `TODO(name):`); they live in `nvim/snippets/all.json`.
- **Theme**: gruvbox ↔ gruvbox_light, or inherit the terminal's (Alacritty), which is followed live.
- **Other**: `:TSContext toggle` pins the function/class context at the top; `za`/`zc`/`zo` fold (treesitter folds with nvim-ufo, everything open on start) and `<leader>z` folds by what the code is: `<leader>zf` the function you are in, `zt` the type, `zo` the object/table literal, `zb` the block (again = the one around it), `zm` the methods of the current type, `zF`/`zT`/`zO` every function/type/object in the file, `za` outline only, `ze` expand all, `zs` focus here (all closed except this), `z1`-`z3` fold everything deeper than that level (all after `<leader>`); `<leader>C` folds long comments (blocks or consecutive `//` lines of `comments.min_lines` or more, 4 by default): `Cc` folds them all and **remembers the preference** (files you open afterwards, and future sessions, open with them already folded; it is saved in `stdpath("state")/comments.json`), `Ce` unfolds them and stops folding them automatically, `Ct` toggles only the one under the cursor without touching the preference; `comments.auto_collapse` only gives the initial value; `:Lazy sync` installs/updates plugins (the config auto-reload does not).

## Light mode

On machines with ≤ 2 GB of RAM, LSP, go.nvim and golangci-lint are turned off (`go vet` remains). Treesitter, conform and nvim-lint keep running.
Force it with `NVIM_LIGHT=1|0`. Per-machine settings in `lua/local.lua` (ignored by git).

## Adding things

- **Language**: `lua/languages/<name>.lua` + add it to `NAMES` in `languages/init.lua` + its page here.
- **Plugin**: one file in `lua/plugins/<group>/`.
- **New keymap**: give it a `desc` of **2+ words starting with its section** (`"Harpoon add file"`); the generator and NvCheatsheet group by the first word and drop single-word ones.
- **Go snippet**: `nvim/snippets/go.json` (VSCode format).
- After changing keys or menus: nothing to edit by hand; `scripts/gen-cheatsheet.sh` regenerates `CHEATSHEET.md` (the `pre-commit` hook does it on its own).
