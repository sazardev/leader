# Cheatsheet

<!-- GENERADO por scripts/gen-cheatsheet.sh — NO editar a mano. -->

> Generado desde los keymaps reales de la config (`nvim_get_keymap`, `menus/`, `servers/on_attach.lua`).
> Se regenera solo en cada commit (`.githooks/pre-commit`). `<leader>` = `Space`.
> Esta es la ÚNICA fuente de teclas. Lo que no se deriva del código (qué hace cada cosa, flujos, herramientas): [`docs/cheatsheets/`](docs/cheatsheets/README.md).

## Menús del leader

Cada menú tiene su letra bajo `<leader>` y solo existe donde aplica: al pulsar `<leader>`
which-key muestra únicamente lo del buffer actual.

| Letra | Menú | Dónde existe |
|---|---|---|
| `<leader>a` | Agent | global |
| `<leader>aD` | Agent DDD | global |
| `<leader>aP` | Agent Repository | global |
| `<leader>aS` | Agent Service | global |
| `<leader>s` | CSS | `css`, `scss`, `less` |
| `<leader>C` | Comments | global |
| `<leader>d` | Dart / Flutter | `dart` |
| `<leader>G` | Git | archivos dentro de un repo git |
| `<leader>g` | Go | `go`, `gomod`, `gowork` |
| `<leader>j` | Java | `java` |
| `<leader>k` | Kotlin | `kotlin` |
| `<leader>m` | Markdown | `markdown` |
| `<leader>p` | Python | `python` |
| `<leader>r` | Rust | `rust` |
| `<leader>P` | Session | global |
| `<leader>S` | Settings | global |
| `<leader>t` | TypeScript / JavaScript | `typescript`, `typescriptreact`, `javascript`, `javascriptreact` |

### Agent — `<leader>a`

_Dónde: global_

| Tecla | Acción |
|---|---|
| `<leader>ai` | implement |
| `<leader>ar` | review |
| `<leader>ae` | explain |
| `<leader>aa` | ask |
| `<leader>af` | fix |
| `<leader>ad` | docs |
| `<leader>aR` | refactor |
| `<leader>ag` | hand off |
| `<leader>am` | model |
| `<leader>ah` | history |
| `<leader>ac` | clear |
| `<leader>ax` | stop |
| `<leader>al` | last answer |

### Agent DDD — `<leader>aD`

_Dónde: global_

| Tecla | Acción |
|---|---|
| `<leader>aDi` | ddd implement |
| `<leader>aDr` | ddd review |
| `<leader>aDf` | ddd fix |
| `<leader>aDm` | ddd missing |
| `<leader>aDa` | ddd ask |
| `<leader>aDd` | ddd diagnose |
| `<leader>aDc` | ddd clear |

### Agent Repository — `<leader>aP`

_Dónde: global_

| Tecla | Acción |
|---|---|
| `<leader>aPp` | repo port |
| `<leader>aPi` | repo implement |
| `<leader>aPr` | repo review |
| `<leader>aPc` | repo check |

### Agent Service — `<leader>aS`

_Dónde: global_

| Tecla | Acción |
|---|---|
| `<leader>aSi` | service implement |
| `<leader>aSr` | service review |
| `<leader>aSd` | service deps |

### CSS — `<leader>s`

_Dónde: `css`, `scss`, `less`_

| Tecla | Acción |
|---|---|
| `<leader>sf` | format |
| `<leader>sc` | toggle color preview |
| `<leader>so` | outline |

### Comments — `<leader>C`

_Dónde: global_

| Tecla | Acción |
|---|---|
| `<leader>Cc` | collapse long comments |
| `<leader>Ce` | expand comments |
| `<leader>Ct` | toggle comment under cursor |
| `<leader>Cd` | doc comment template for this function/type |
| `<leader>Cm` | public functions missing a doc comment (quickfix) |

### Dart / Flutter — `<leader>d`

_Dónde: `dart`_

| Tecla | Acción |
|---|---|
| `<leader>dr` | run |
| `<leader>dd` | debug |
| `<leader>dh` | hot reload |
| `<leader>dR` | hot restart |
| `<leader>dq` | quit app |
| `<leader>dD` | devices |
| `<leader>de` | emulators |
| `<leader>do` | widget outline |
| `<leader>dl` | log toggle |
| `<leader>dt` | devtools |
| `<leader>dp` | pub get |
| `<leader>dm` | test (flutter or dart, auto-detected) |
| `<leader>dv` | analyze |
| `<leader>dx` | dart fix --apply |
| `<leader>df` | format |

### Git — `<leader>G`

_Dónde: archivos dentro de un repo git_

| Tecla | Acción |
|---|---|
| `<leader>Gc` | commit (type, scope, subject) |
| `<leader>Gm` | commit message written by AI (review first) |
| `<leader>Ga` | amend last commit message |
| `<leader>Gt` | status |
| `<leader>Gb` | blame toggle |
| `<leader>Gd` | diff of all changes (Diffview) |
| `<leader>Gf` | history of this file |
| `<leader>Gr` | history of the repo |
| `<leader>Gq` | close Diffview |
| `<leader>Go` | conflict: keep ours |
| `<leader>GT` | conflict: keep theirs |
| `<leader>GB` | conflict: keep both |
| `<leader>GN` | conflict: keep none |
| `<leader>Gn` | conflict: next |
| `<leader>Gp` | conflict: previous |
| `<leader>Gl` | conflicts of the repo (quickfix) |

### Go — `<leader>g`

_Dónde: `go`, `gomod`, `gowork`_

| Tecla | Acción |
|---|---|
| `<leader>ga` | struct: add json tags (snake_case) |
| `<leader>gA` | struct: add json tags + omitempty |
| `<leader>gD` | struct: remove json tags |
| `<leader>gs` | struct: fill literal |
| `<leader>ge` | if err != nil for the call under the cursor |
| `<leader>gT` | add test for the function under the cursor |
| `<leader>gr` | run |
| `<leader>gb` | build |
| `<leader>gv` | lint (golangci-lint, or go vet if missing) |
| `<leader>gf` | format |
| `<leader>gt` | go mod tidy |
| `<leader>gx` | golangci-lint --fix |
| `<leader>gm` | go test ./... |
| `<leader>gR` | go test -race ./... |
| `<leader>gc` | go test -cover ./... |
| `<leader>gp` | go fix -diff (modernizers preview) |
| `<leader>gi` | go fix (apply modernizers) |
| `<leader>gg` | go generate ./... |
| `<leader>gu` | go get -u + go mod tidy |

### Java — `<leader>j`

_Dónde: `java`_

| Tecla | Acción |
|---|---|
| `<leader>jr` | run |
| `<leader>jb` | build |
| `<leader>jm` | test |
| `<leader>jv` | check / verify |
| `<leader>jc` | clean |

### Kotlin — `<leader>k`

_Dónde: `kotlin`_

| Tecla | Acción |
|---|---|
| `<leader>kr` | run |
| `<leader>kb` | build |
| `<leader>km` | test |
| `<leader>kv` | check / verify |
| `<leader>kc` | clean |

### Markdown — `<leader>m`

_Dónde: `markdown`_

| Tecla | Acción |
|---|---|
| `<leader>mr` | toggle render |
| `<leader>md` | toggle linter diagnostics (this buffer only) |
| `<leader>mz` | reading mode (centered, distraction-free) |
| `<leader>ms` | spell check (es, en) |
| `<leader>mw` | word count and reading time |
| `<leader>mx` | toggle checkbox |
| `<leader>mo` | outline |
| `<leader>mf` | format |

### Python — `<leader>p`

_Dónde: `python`_

| Tecla | Acción |
|---|---|
| `<leader>pr` | run file |
| `<leader>pi` | REPL with the file |
| `<leader>pm` | pytest (whole project) |
| `<leader>pt` | pytest (current file) |
| `<leader>pv` | ruff check . |
| `<leader>px` | ruff check --fix . |
| `<leader>pf` | ruff format (current file) |

### Rust — `<leader>r`

_Dónde: `rust`_

| Tecla | Acción |
|---|---|
| `<leader>rr` | cargo run |
| `<leader>rb` | cargo build |
| `<leader>rm` | cargo test |
| `<leader>rc` | cargo check |
| `<leader>rv` | cargo clippy |
| `<leader>rx` | cargo clippy --fix --allow-dirty |
| `<leader>rf` | cargo fmt |

### Session — `<leader>P`

_Dónde: global_

| Tecla | Acción |
|---|---|
| `<leader>Pr` | restore session (this folder) |
| `<leader>Ps` | select session (any project) |
| `<leader>Pl` | restore last session |
| `<leader>Pw` | save session now |
| `<leader>Px` | don't save on exit |

### Settings — `<leader>S`

_Dónde: global_

| Tecla | Acción |
|---|---|
| `<leader>St` | toggle theme |
| `<leader>Sd` | default theme (gruvbox) |
| `<leader>Sa` | terminal theme (Alacritty) |
| `<leader>Sr` | re-sync terminal theme |
| `<leader>Sp` | theme picker |
| `<leader>Si` | theme info |

### TypeScript / JavaScript — `<leader>t`

_Dónde: `typescript`, `typescriptreact`, `javascript`, `javascriptreact`_

| Tecla | Acción |
|---|---|
| `<leader>tr` | run a package.json script (picker) |
| `<leader>td` | dev (script `dev`) |
| `<leader>tb` | build (script `build`) |
| `<leader>tm` | test (package manager) |
| `<leader>tv` | lint (script `lint`, else eslint .) |
| `<leader>tc` | typecheck (tsc --noEmit) |
| `<leader>tx` | eslint --fix (current file) |
| `<leader>tf` | format |
| `<leader>to` | organize imports |
| `<leader>ti` | install dependencies |

## LSP (al adjuntar un servidor)

Keymaps buffer-locales de `servers/on_attach.lua`.

| Tecla | Acción |
|---|---|
| `<leader>ca` | code action |
| `gd` | go to DEFINITION |
| `grr` | see WHERE IT'S USED (list) |

## Autocompletado (blink.cmp, modo insert)

Preset `enter` más los overrides de `plugins/editing/blink.lua`. `→` = se prueba en orden hasta que uno aplica.

| Tecla | Acción |
|---|---|
| `<C-b>` | scroll documentation up |
| `<C-e>` | close menu |
| `<C-f>` | scroll documentation down |
| `<C-k>` | show signature help → hide signature help |
| `<C-n>` | next item |
| `<C-p>` | previous item |
| `<C-space>` | open menu → show documentation → hide documentation |
| `<CR>` | accept Go `ErrX` ghost text + new line → accept item |
| `<Esc>` | close menu |
| `<S-Tab>` | previous item → jump to previous snippet placeholder (when no menu is open) |
| `<Tab>` | accept Go `ErrX` ghost text → next item → jump to next snippet placeholder (when no menu is open) |

## nvim-tree (dentro del árbol)

`Ctrl+n` lo abre/cierra y `<leader>e` lo enfoca (ver Atajos globales). `g?` dentro del árbol lista estas mismas teclas.

| Tecla | Acción |
|---|---|
| `-` | Up |
| `.` | Run Command |
| `<2-LeftMouse>` | Open |
| `<2-RightMouse>` | CD |
| `<BS>` | Close Directory |
| `<C-]>` | CD |
| `<C-e>` | Open: In Place |
| `<C-k>` | Info |
| `<C-r>` | Rename: Omit Filename |
| `<C-t>` | Open: New Tab |
| `<C-v>` | Open: Vertical Split |
| `<C-x>` | Open: Horizontal Split |
| `<CR>` | Open file and close tree |
| `<Del>` | Delete |
| `<Tab>` | Open Preview |
| `<leader>nd` | New folder(s) |
| `<leader>nx` | Delete folder with contents |
| `<lt>` | Previous Sibling |
| `>` | Next Sibling |
| `B` | Toggle Filter: No Buffer |
| `C` | Toggle Filter: Git Clean |
| `D` | Trash |
| `E` | Expand All |
| `F` | Live Filter: Clear |
| `H` | Toggle Filter: Dotfiles |
| `I` | Toggle Filter: Git Ignored |
| `J` | Last Sibling |
| `K` | First Sibling |
| `L` | Toggle Group Empty |
| `M` | Toggle Filter: No Bookmark |
| `O` | Open: No Window Picker |
| `P` | Parent Directory |
| `R` | Refresh |
| `S` | Search |
| `U` | Toggle Filter: Custom |
| `W` | Collapse All |
| `Y` | Copy Relative Path |
| `[c` | Prev Git |
| `[e` | Prev Diagnostic |
| `]c` | Next Git |
| `]e` | Next Diagnostic |
| `a` | Create File Or Directory |
| `bd` | Delete Bookmarked |
| `bmv` | Move Bookmarked |
| `bt` | Trash Bookmarked |
| `c` | Copy |
| `d` | Delete |
| `e` | Rename: Basename |
| `f` | Live Filter: Start |
| `g?` | Help |
| `ge` | Copy Basename |
| `gp` | Move |
| `gy` | Copy Absolute Path |
| `m` | Toggle Bookmark |
| `o` | Open |
| `p` | Paste |
| `q` | Close |
| `r` | Rename |
| `s` | Run System |
| `u` | Rename: Full Path |
| `x` | Cut |
| `y` | Copy Name |

## Atajos globales

Secciones = primera palabra del `desc` (igual que el botón **Mappings** del dashboard).

### Agent

| Tecla | Modo | Acción |
|---|---|---|
| `<leader>aDa` | n,x | Ddd ask |
| `<leader>aDc` | n | Ddd clear |
| `<leader>aDd` | n | Ddd diagnose |
| `<leader>aDf` | n,x | Ddd fix |
| `<leader>aDi` | n,x | Ddd implement |
| `<leader>aDm` | n,x | Ddd missing |
| `<leader>aDr` | n,x | Ddd review |
| `<leader>aPc` | n | Repo check |
| `<leader>aPi` | n,x | Repo implement |
| `<leader>aPp` | n,x | Repo port |
| `<leader>aPr` | n,x | Repo review |
| `<leader>aR` | n,x | Refactor |
| `<leader>aSd` | n | Service deps |
| `<leader>aSi` | n,x | Service implement |
| `<leader>aSr` | n,x | Service review |
| `<leader>aa` | n,x | Ask |
| `<leader>ac` | n | Clear |
| `<leader>ad` | n,x | Docs |
| `<leader>ae` | n,x | Explain |
| `<leader>af` | n,x | Fix |
| `<leader>ag` | n,x | Hand off |
| `<leader>ah` | n | History |
| `<leader>ai` | n,x | Implement |
| `<leader>al` | n | Last answer |
| `<leader>am` | n | Model |
| `<leader>ar` | n,x | Review |
| `<leader>ax` | n | Stop |

### Comment

| Tecla | Modo | Acción |
|---|---|---|
| `<leader>/` | n,x | Comment |

### Comments

| Tecla | Modo | Acción |
|---|---|---|
| `<leader>Cc` | n | Collapse long comments |
| `<leader>Cd` | n | Doc comment template for this function/type |
| `<leader>Ce` | n | Expand comments |
| `<leader>Cm` | n | Public functions missing a doc comment (quickfix) |
| `<leader>Ct` | n | Toggle comment under cursor |

### Diagnostics

| Tecla | Modo | Acción |
|---|---|---|
| `<leader>xa` | n | Blocks inline (toggle) |
| `<leader>xc` | n | Blocks collapse / expand |
| `<leader>xd` | n | Line popup (press again to enter) |
| `<leader>xn` | n | Next block |
| `<leader>xp` | n | Previous block |
| `<leader>xx` | n | Project list (Trouble) |

### Find

| Tecla | Modo | Acción |
|---|---|---|
| `<leader>H` | n | File history (session) |
| `<leader>fr` | n | Replace in project (grug-far) |

### Flash

| Tecla | Modo | Acción |
|---|---|---|
| `S` | n,x,o | Treesitter |
| `s` | n,x,o | Jump |

### General

| Tecla | Modo | Acción |
|---|---|---|
| `;` | n | Command mode (; instead of :) |
| `<C-c>` | n | Copy whole file |
| `<C-s>` | n | Save file |
| `<Esc>` | n | Go back after jump / clear highlight |
| `<leader>d` | n,x | Delete without copying |
| `<leader>fm` | n,x | Format file |
| `<leader>q` | n | Close buffer / quit |
| `<leader>w` | n | Save |
| `jk` | i | Leave insert (closes the completion menu first) |

### Harpoon

| Tecla | Modo | Acción |
|---|---|---|
| `<leader>h1` | n | Jump to file 1 |
| `<leader>h2` | n | Jump to file 2 |
| `<leader>h3` | n | Jump to file 3 |
| `<leader>h4` | n | Jump to file 4 |
| `<leader>ha` | n | Add file |
| `<leader>hm` | n | Menu |

### LSP

| Tecla | Modo | Acción |
|---|---|---|
| `<C-LeftMouse>` | n | Go to DEFINITION (Ctrl+click) |

### Move

| Tecla | Modo | Acción |
|---|---|---|
| `<A-h>` | x | Left |
| `<A-h>` | n | Line left |
| `<A-j>` | x | Down |
| `<A-j>` | n | Line down |
| `<A-k>` | x | Up |
| `<A-k>` | n | Line up |
| `<A-l>` | x | Right |
| `<A-l>` | n | Line right |
| `<C-b>` | i | Beginning of line |
| `<C-e>` | i | End of line |
| `<C-h>` | i | Left |
| `<C-j>` | i | Down |
| `<C-k>` | i | Up |
| `<C-l>` | i | Right |

### Multicursor

| Tecla | Modo | Acción |
|---|---|---|
| `<A-LeftMouse>` | n | Toggle cursor at mouse |
| `<A-N>` | n,x | Skip next match |
| `<A-P>` | n,x | Skip previous match |
| `<A-a>` | n,x | Add cursor on every match |
| `<A-n>` | n,x | Add next match |
| `<A-p>` | n,x | Add previous match |
| `<C-Down>` | n,x | Add cursor below |
| `<C-Up>` | n,x | Add cursor above |

### Nvim-tree

| Tecla | Modo | Acción |
|---|---|---|
| `<C-n>` | n | Toggle window |
| `<leader>e` | n | Focus window |

### Session

| Tecla | Modo | Acción |
|---|---|---|
| `<leader>Pl` | n | Restore last session |
| `<leader>Pr` | n | Restore session (this folder) |
| `<leader>Ps` | n | Select session (any project) |
| `<leader>Pw` | n | Save session now |
| `<leader>Px` | n | Don't save on exit |

### Settings

| Tecla | Modo | Acción |
|---|---|---|
| `<leader>Sa` | n | Terminal theme (Alacritty) |
| `<leader>Sd` | n | Default theme (gruvbox) |
| `<leader>Si` | n | Theme info |
| `<leader>Sp` | n | Theme picker |
| `<leader>Sr` | n | Re-sync terminal theme |
| `<leader>St` | n | Toggle theme |

### Surround

| Tecla | Modo | Acción |
|---|---|---|
| `sa` | n,x | Add |
| `sd` | n | Delete |
| `sr` | n | Replace |

### Telescope

| Tecla | Modo | Acción |
|---|---|---|
| `<leader>fb` | n | Find buffers |
| `<leader>ff` | n | Find files |
| `<leader>fo` | n | Find oldfiles |
| `<leader>fw` | n | Live grep |

### Terminal

| Tecla | Modo | Acción |
|---|---|---|
| `<A-i>` | n,t | Toggle floating term |
| `<A-v>` | n,t | Toggleable vertical term |
| `<C-x>` | t | Escape terminal mode |

### Textobject

| Tecla | Modo | Acción |
|---|---|---|
| `<End>` | n,x | Block end (End) |
| `<Home>` | n,x | Block start (Home) |
| `<PageDown>` | n,x | Next block (PageDown) |
| `<PageUp>` | n,x | Previous block (PageUp) |
| `[f` | n,x,o | Previous function |
| `]f` | n,x,o | Next function |
| `ac` | x,o | Outer class |
| `af` | x,o | Outer function |
| `ic` | x,o | Inner class |
| `if` | x,o | Inner function |

### Window

| Tecla | Modo | Acción |
|---|---|---|
| `<C-h>` | n | Window left |
| `<C-j>` | n | Window down |
| `<C-k>` | n | Window up |
| `<C-l>` | n | Window right |

## Nativos de Neovim 0.11 (no son de esta config)

| Tecla | Acción |
|---|---|
| `grn` | renombrar símbolo |
| `gra` | code action |
| `gri` | ir a la implementación |
| `grt` | ir a la definición del tipo |
| `gO` | símbolos del documento |
| `K` | hover (documentación) |
| `gx` | abrir la URL o ruta bajo el cursor |
| `gc / gcc` | comentar (operador / línea) |

