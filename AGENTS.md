# my-nvim-setup

Neovim + NvChad v2.5 config — not an application. No tests, CI, or build system.

## Repo structure

- `nvim/` — mirrors `%LOCALAPPDATA%\nvim` on Windows. Symlink it:

  ```powershell
  New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\nvim" -Target "C:\path\to\my-nvim-setup\nvim"
  ```

- `.agents/skills/caveman*` — OpenCode skills (lockfile: `skills-lock.json`)
- `CHEATSHEET.md` — **GENERADO**, no se edita: todas las teclas (menús del leader, LSP, autocompletado, nvim-tree, globales) leídas de los keymaps reales por `scripts/gen-cheatsheet.sh`; el hook `.githooks/pre-commit` lo regenera si el commit toca `nvim/`. `scripts/gen-cheatsheet.sh --check` falla si está desactualizado. Es la ÚNICA fuente de teclas: no copies tablas de teclas a los docs
- `docs/cheatsheets/` — solo lo que NO se deriva del código (qué hace cada cosa, flujos, herramientas, trampas): `README.md` + una página por lenguaje (`go.md` es la más detallada). Al cambiar menús, snippets o herramientas de un lenguaje, actualiza su página; sin tablas de teclas (esas salen del código)
- `scripts/` — `gen-cheatsheet.sh` (+ `.lua`): generador del cheatsheet (nvim headless con la config real, ignora `local.lua` vía `NVIM_NO_LOCAL=1`)
- `.gitignore` — excludes `.claude/` (machine-specific Claude config)

## How it works

- Plugins auto-install via `lazy.nvim` on first open
- Activate the auto-reload hook once per clone: `git config core.hooksPath .githooks` (the hook picks the right data dir for Windows or Linux)
- LSP servers and tools (gopls, vtsls, stylua, prettier, eslint_d, dart, etc.) auto-install via `mason-tool-installer`
- No manual setup beyond the symlink
- **Auto-reload**: `.githooks/post-merge` creates a marker on `git pull`; `core/autocmds/reload.lua` detects it on `UIEnter` and runs `luafile $MYVIMRC` to reload config automatically

## Architecture

Un archivo = una responsabilidad. Entrada mínima en `nvim/init.lua`; todo lo demás es modular:

```
nvim/
├── init.lua                  # solo bootstrap (lazy + core)
└── lua/
    ├── core/                 # arranque: settings, light, lazy, options, clipboard, theme
    │   ├── settings.lua      #   TODOS los ajustes configurables (+ overrides locales)
    │   ├── keymaps/          #   cleanup (quita NvChad) · general
    │   └── autocmds/         #   reload · treesitter · ui
    ├── languages/            # 1 archivo por lenguaje: DECLARA treesitter, lsp, mason, formatters, linters, menú
    │   ├── init.lua          #   registro: agrega las declaraciones y las sirve a cada consumidor
    │   └── actions/          #   acciones de los menús (go, dart, typescript, python, rust, jvm...)
    ├── appearance/           # tema por defecto vs heredado de la terminal (Alacritty → base46)
    ├── themes/               # temas de usuario de base46 (terminal.lua se genera de la paleta)
    ├── servers/              # overrides por servidor LSP (servers/<nombre>.lua) + cargador
    ├── menus/                # menús contextuales del leader (buffer-locales) + contexto Git
    ├── plugins/<grupo>/      # 1 spec de lazy por plugin: core lsp tools syntax languages navigation editing git ui
    ├── ui/                   # dashboard (+ arts/: catálogo de arte ASCII), highlights, lualine
    ├── utils/                # helpers puros: terminal, project, actions, git, log, telescope
    └── chadrc.lua            # solo compone: tema + dashboard + ui de NvChad
```

**Añadir un lenguaje**: crea `lua/languages/<nombre>.lua` (contrato en `languages/init.lua`) y agrégalo a `NAMES`. No hay que tocar mason, treesitter, conform, nvim-lint ni LSP: salen del registro. Overrides de un servidor: `lua/servers/<servidor>.lua`.

**Añadir un plugin**: un archivo en `lua/plugins/<grupo>/`. Grupos nuevos: agrégalos a `GROUPS` en `core/lazy.lua`.

**Añadir un arte al dashboard**: crea `lua/ui/arts/<nombre>.lua` (devuelve la lista de líneas; **solo arte de puntos braille**, U+2800–U+28FF, nada de ASCII/bloques). Se descubre solo: `ui/arts/init.lua` escanea la carpeta, sin lista que mantener. Se elige desde el botón "Change Art" (`ca`) del dashboard; la elección se guarda en `stdpath("state")/dashboard.json`. Valor inicial: `settings.dashboard.art`.

**Tema heredado de la terminal** (`<leader>S`): lee `alacritty.toml` (Linux, Windows o WSL en `/mnt/*/Users/*/AppData`), resuelve sus `import` y genera un tema de base46 (`lua/themes/terminal.lua`) con el fondo exacto de la terminal, grises interpolados y acentos con contraste mínimo (`theme.terminal.min_contrast`). Se recuerda entre sesiones (estado en `stdpath("state")/appearance.json` + marcador junto a la caché de base46) y se sigue EN VIVO: mientras el tema activo es el terminal, un sondeo (`theme.terminal.watch_ms`, 1000 ms; 0 = apagado) hace `stat` de los archivos de la config y recompila al detectar un cambio (inotify no sirve: en WSL la config está en `/mnt/c`). Con el tema por defecto no corre nada. También re-sincroniza al abrir nvim y al volver el foco. Ruta personalizada: `theme.terminal.config`.

**Ajustes por máquina**: `lua/local.lua` (ignorado por git) devuelve una tabla parcial que se mezcla sobre `core/settings.lua` (tema, lenguajes desactivados, format-on-save, opciones de vim, clipboard, modo ligero...). Ejemplo: `return { languages = { disabled = { "astro" } } }`.

## Key tools included

| Category   | Tools                                                                                                                                                          |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| LSP        | gopls, vtsls, tailwindcss, eslint, jsonls+schemastore, prismals, dockerls, astro                                                                               |
| Formatters | stylua, goimports+gofumpt, prettier, dart_format                                                                                                               |
| Linters    | golangci-lint (govet in light mode), eslint_d, markdownlint, jsonlint, ysc (YarnSpinner)                                                                       |
| Completion | blink.cmp, mini.pairs                                                                                                                                          |
| Terminal   | toggleterm, lazydocker (via TermExec)                                                                                                                          |
| Navigation | harpoon (<leader>h*), flash.nvim (s/S), aerial (symbol outline), nvim-ufo (folds)                                                                              |
| UI         | lualine, gitsigns, treesitter-context (`:TSContext toggle`), vim-illuminate, render-markdown, todo-comments, nvim-highlight-colors (hex/rgb/Tailwind preview)                                            |
| Other      | lazydev (tipos de la API de nvim en Lua), git-conflict (<leader>Go/GT/GB/GN/Gn/Gp/Gl), Telescope+fzf-native, nvim-tree, Trouble, autotag, git-blame, grug-far (<leader>fr global replace), diffview (<leader>Gd diff, <leader>Gf/Gr historial), mini.surround, mini.move (Alt+hjkl), neoconf, package-info, persistence (sesiones) |

## Performance

- **git-blame** is off by default — toggle with `<leader>Gb` (no `BufRead` overhead)
- **Telescope** respects `.gitignore` in `find_files` (skip `node_modules`, `dist/`, etc.)
- **nvim-tree** hides git-ignored dirs by default — toggle with `I` or `git.ignore = false`
- Plugins are lazy-loaded via events, ft, cmd, or keys (not on startup)

- `ftdetect/yarnspinner.vim` — `*.yarn` → `yarnspinner` filetype
- `syntax/yarnspinner.vim` — syntax highlighting for YarnSpinner dialogue scripts

## Gotchas

- **Clipboard (WSL/SSH sin DISPLAY)**: `core/clipboard.lua` usa OSC 52 para copiar (Alacritty + herdr lo reenvían); pegar desde el sistema es Ctrl+Shift+V en la terminal
- **ysc (YarnSpinner linter)** es opcional: se activa solo si `ysc` está en el PATH (`dotnet tool install -g yarn-spinner`, requiere `dotnet`)
- **`:checkhealth mason`** avisa de ruby/gem/php/java/julia/composer/luarocks ausentes: es solo informativo, ningún tool de la config los necesita
- **Menús contextuales del leader** (`lua/menus/` + campo `menu` de cada lenguaje): cada lenguaje tiene su letra y solo existe en buffers de ese filetype (g Go, d Dart, r Rust, p Python, t TS/JS, m Markdown, s CSS, j Java, k Kotlin); `<leader>G` Git solo dentro de un repo. Para añadir un lenguaje: nueva entrada en la tabla `langs`. No definas un mapeo que sea a la vez acción y prefijo de otros (p. ej. `<leader>h` + `<leader>h1`): which-key lo resuelve tras `timeoutlen` y cierra el popup
- **Sesiones** (`persistence.nvim`, `utils/session.lua`, menú global `<leader>P`): guarda buffers y ventanas al salir, una por carpeta (y por rama de git; `main`/`master` usan la base). NO se restauran solas: botón "Restore Session" (`rs`) del dashboard (solo si hay sesión para esa carpeta) o `<leader>Pr`; `<leader>Ps` elige proyecto, `<leader>Pl` la última, `<leader>Pw` guarda ya, `<leader>Px` no guarda al salir. Antes de guardar se cierran las ventanas auxiliares (árbol, terminal, outline). Abrir un solo archivo (`nvim x`) y salir sobrescribe la sesión de esa carpeta: usa `<leader>Px` si no quieres. Qué incluye: `options.sessionoptions` en `core/settings.lua`. El deshacer persistente (`undofile`) ya lo activa NvChad
- **Autoread** (`core/autocmds/autoread.lua`): `autoread` + `checktime` en `FocusGained`/`TermClose`/`TermLeave` recargan lo que cambian git o los formatters fuera de nvim (nunca pisa buffers con cambios sin guardar). Búsqueda con `ignorecase`+`smartcase` e `inccommand=split` (vista previa de `:s`) en `options`
- **git-conflict.nvim**: sin mapeos por defecto (`co`/`cb` pisarían operadores `c`); las acciones viven en el menú `<leader>G` (o ours, T theirs, B both, N none, n/p siguiente/anterior, l lista en quickfix)
- **Go: tags de struct y snippets**: `utils/gotags.lua` es una fuente de blink.cmp (solo `go`) que deriva el tag del NOMBRE del campo: en `SentAt time.Time ` + backtick sugiere `json:"sent_at"` (+ `,omitempty`, camelCase, yaml, db...); tras `json:` o `json:"` sugiere el valor y tras `,` las opciones (`omitempty`, `omitzero`, `string`). Dentro de un tag el primer ítem viene preseleccionado (Enter acepta; fuera de ahí `preselect` sigue apagado). Con `gorm`: `gorm:"` sugiere valores completos según nombre y TIPO del campo (`primaryKey;type:text`, `type:text;not null`, `autoCreateTime`, `foreignKey:XID`...; sin `not null` si es puntero) y tras `;` opciones sueltas (separador `;`, no `,`; textEdit desde el último `;`); el menú de claves del backtick también lista las variantes gorm tras json. `utils/gomodel.lua` (solo `*_model.go` o `model.go`; lo llama gosmart al empezar una declaración y pone sus ítems AL PRINCIPIO de la lista): `functable` → `func (XModel) TableName() string` (nombre derivado: sin `Model`, snake_case, plural), `funcdomain` (toDomain + fromDomain), `functodomain`, `funcfromdomain` (`func (m NoteModel) toDomain() *note.Note` / `fromDomain(n *note.Note) NoteModel`; dominio `NoteModel`→`note.Note`; el constructor se busca en el paquete importado y, si no está, `Reconstitute` queda como placeholder). Con varios structs: `functable X`, `from<Base>Domain`. Solo para structs que aún no tienen la función. Para structs ya escritos: `<leader>ga` (json snake_case), `<leader>gA` (+omitempty), `<leader>gD` (quitar) vía go.nvim/gomodifytags; también `<leader>gs` fill struct, `<leader>ge` if err, `<leader>gT` add test. Snippets propios en `nvim/snippets/go.json` (formato VSCode, los lee blink junto a friendly-snippets) con NOMBRES COMPLETOS, sin siglas, solo de SENTENCIAS y utilidades (`iferr`, `errorsis`, `waitgroup`, `contexttimeout`, `testtable`, `httphandlerjson`...). `utils/gosmart.lua` (treesitter) es la fuente contextual: al EMPEZAR una declaración (`func`, `type` o `New…` en columna 0) ofrece variantes de `func` (simple, `error`, `value`, `pointer`, `bool`, `result error`, `pointer error`, `ctx error`, `ctx result error`, `main`, `init`), métodos de CADA struct del archivo (puntero, `error`, valor, `String`), `NewX(campos…)` para los structs sin constructor y variantes de `type` (struct, struct constructor, generic, interface*, enum string/iota, defined, func, error, options); tras `type Envelope ` → `struct`/`interface`/`func`; con el nombre de un struct del paquete en posición de VALOR (`x := Env`, `return Env`, argumentos) Enter inserta el literal YA relleno (Tab de valor en valor; en posición de tipo no aplica); dentro de un literal `Envelope{ }` (struct del mismo paquete) abre el menú solo al pulsar Enter y ofrece `fill all fields` + los campos que faltan con valores por defecto; dentro de `interface { }` → firmas de método (`method error`, `method ctx result error`, embed...). Ahí mismo se silencia el ruido: sin palabras del buffer ni el `func`/`type` genérico del LSP, y los snippets de sentencia solo salen dentro de funciones (los de declaración, a nivel de paquete).
- **Convención de `desc` en keymaps**: 2+ palabras y la PRIMERA es la sección (`"Harpoon add file"`, `"Go run"`, `"General save"`). El botón Mappings del dashboard (`NvCheatsheet`) y `CHEATSHEET.md` agrupan por esa palabra y descartan los desc de una sola (el generador avisa). Los menús del leader lo cumplen solos (`menus.desc` antepone la 1ª palabra del nombre del menú). Las teclas nativas de Neovim se excluyen midiendo `nvim --clean`; los grupos nativos que aún cuelan en NvCheatsheet van en `excluded_groups` (`ui/dashboard.lua`)
- **blink.cmp: Tab/Esc/jk** (`plugins/editing/blink.lua`, `utils/blinkkeys.lua`, `core/keymaps/general.lua`): con el menú abierto `Tab`/`S-Tab` eligen sugerencia; sin menú, dentro de un snippet saltan de hueco. `Esc` y `jk` con el menú abierto SOLO lo cierran (`cancel`: deshace el auto_insert, vuelve a lo tecleado) y mantienen insert + snippet; sin menú salen de insert. Flujo para conservar lo tecleado en un hueco: `Esc` y luego `Tab`. No pongas el salto de snippet ANTES de `select_next` en `<Tab>`: impide elegir sugerencias dentro de un snippet
- **Treesitter** compila parsers con el compilador de C del sistema (`gcc`) y requiere el binario `tree-sitter` (`tree-sitter-cli`)
- **No standalone run**: this is a config repo, must be symlinked to Neovim's config path
- **lazy-lock.json** committed for reproducible plugin versions
- `.claude/settings.local.json` is NOT committed (machine-specific permissions)
- **Astro formatting** requires `prettier-plugin-astro` in the project's `node_modules` or installed globally — Mason only installs `prettier` itself
- **mini.surround** keymaps: `sa` add, `sd` delete, `sr` replace surrounding delimiters
- **flash.nvim** keymaps: `s` jump to any word label, `S` jump to treesitter nodes (preserves native `r` replace char)
- **telescope-fzf-native** requires `cmake` installed on the system (auto-disabled if missing via `enabled`)
- **Auto-reload limitation**: `luafile $MYVIMRC` reloads Lua config but does NOT install/remove plugins or treesitter parsers. For plugin changes, use `:Lazy sync` or restart nvim.
- **Light mode** (`nvim/lua/core/light.lua`): auto-detects RAM ≤ 2GB and disables all resident stuff — LSP servers, go.nvim, golangci-lint (falls back to `go vet`). Mason installs only `goimports`+`gofumpt`. Keeps treesitter + conform (ephemeral formatters) + nvim-lint. Override with `NVIM_LIGHT=1|0` env, `settings.light.force` or `vim.g.light_mode`.
