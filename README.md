# my-nvim-setup

Config de **Neovim** sobre NvChad v2.5, pensada como un pequeño **framework**: la clonas, corres un script y tienes un
editor listo para trabajar, con lo que un desarrollador usa a diario y nada más. Minimalismo, productividad rápida y
rendimiento: todo se carga perezosamente, un archivo = una responsabilidad, y lo que no usas se apaga con una línea.

`v1.0.0` · Neovim ≥ 0.11 · Linux, WSL, macOS y Windows

## Instalación

```sh
git clone <url-de-este-repo> ~/my-nvim-setup
cd ~/my-nvim-setup
./install.sh
```

El script (idempotente, puedes repetirlo) hace todo:

1. instala lo que falte del sistema (git, curl, compilador de C, ripgrep, node, cmake) y **Neovim ≥ 0.11** si no lo tienes
   (en `~/.local/opt`, sin `sudo`; con brew en macOS) — siempre preguntando antes;
2. enlaza `nvim/` como tu config (`~/.config/nvim`) guardando la anterior como `nvim.bak-<fecha>`;
3. activa los hooks de git (`.githooks`: cheatsheet siempre al día y commits convencionales);
4. escribe tus **ajustes por máquina** (`nvim/lua/local.lua`, ignorado por git) si los pides con las opciones de abajo;
5. instala los plugins (lazy.nvim, versiones fijadas en `nvim/lazy-lock.json`), los LSP/formatters/linters (Mason) y
   compila los parsers de treesitter (`tree-sitter-cli` viene de Mason);
6. **configura el agente de IA** si lo pides (o te enseña lo que detecta: Claude Code, OpenCode, Ollama…).

Después abre `nvim`. Pulsa `<Space>` y which-key te enseña los menús.

| Opción | Efecto |
|---|---|
| `-y` | sin preguntas |
| `--lang go,typescript` | solo esos lenguajes (+ lua): el resto se desactiva en `local.lua`, así no se instala nada que no uses |
| `--theme catppuccin` | tema por defecto (`local.lua`) |
| `--light` / `--no-light` | fuerza el modo ligero (sin LSP residente) o lo apaga; sin esto se detecta por RAM (≤ 2 GB) |
| `--agent auto` | configura el agente: `auto` (lo mejor que haya), `claude/haiku`, `ollama/qwen2.5-coder:7b@light`…; `none` lo omite; sin la opción solo enseña lo que detecta |
| `--no-deps` | no toca paquetes del sistema ni Neovim |
| `--no-plugins` | solo enlaza; plugins y herramientas se instalan solos la primera vez que abras nvim |
| `--dry-run` | muestra lo que haría |

```sh
./install.sh -y --lang go,lua --theme gruvbox --agent auto      # un portátil para Go, todo configurado
./install.sh --dry-run --no-deps --lang rust                     # ver qué haría
```

Lenguajes disponibles: `lua go typescript html css tailwind json yaml toml markdown docker prisma astro dart rust python java kotlin yarnspinner`.
Si `local.lua` ya existe **no se toca**: el instalador te dice qué añadir (es tuyo y puede tener otros ajustes).

**Windows nativo** (PowerShell): `./install.ps1 [-Lang go,typescript] [-Theme x] [-Light|-NoLight] [-Agent auto] [-NoPlugins]` crea el
junction en `%LOCALAPPDATA%\nvim` y hace los mismos pasos (escrito pero no probado en Windows real; en WSL usa `install.sh`).

**Desinstalar**: borra el enlace `~/.config/nvim` (y, si quieres, `~/.local/share/nvim`, `~/.local/state/nvim`, `~/.cache/nvim`).

## Filosofía

- **Rápido**: arranque de ~20 ms (medido en headless, con `--startuptime`); `defaults.lazy = true`, plugins por evento/filetipo/comando/tecla, cache de bytecode (`vim.loader`) y plugins nativos innecesarios desactivados.
- **Mínimo**: 54 entradas en `lazy-lock.json`, **contando** dependencias y las del propio NvChad. Sin gestor de sesiones pesado, sin barra de tabs, sin chat de IA embebido, sin árbol de dependencias de LSP que no uses.
- **Modular**: la config se *declara*, no se cablea. Añadir un lenguaje, un plugin, una acción del agente o una ayuda de Go es crear un archivo; nada más se toca.
- **Gasta lo mínimo**: lo que se puede decidir sin modelo se decide antes (puertas, análisis local, completado con treesitter); cuando hay que llamar a uno, se manda solo lo necesario y se dice cuánto cuesta.
- **Ligero donde hace falta**: con ≤ 2 GB de RAM se apagan automáticamente los procesos residentes (LSP, golangci-lint); se fuerza con `NVIM_LIGHT=1|0`.
- **Todo con teclado**, teclas documentadas y generadas desde el código real.

## Qué incluye

| Área | Contenido |
|---|---|
| Lenguajes | Go, TypeScript/JS/TSX, HTML/CSS/Tailwind/Astro, Python, Rust, Dart/Flutter, Java/Kotlin, Lua, Markdown, JSON/YAML/TOML, Docker, Prisma, YarnSpinner. Cada uno declara su LSP, formatter, linter, parsers y su menú `<leader>` (solo existe en buffers de ese filetipo) |
| Edición | blink.cmp, mini.pairs/surround/move, multicursor, flash (saltos), textobjects de treesitter, folds (ufo) con comentarios largos plegables, snippets propios |
| Navegación | Telescope (+fzf), nvim-tree, harpoon, aerial (símbolos), grug-far (reemplazo global), historial de archivos |
| Git | gitsigns, diffview, git-conflict, git-blame (apagado por defecto) y **commits convencionales** (ver abajo) |
| Diagnóstico | bloques en línea bajo su línea, número de línea con la severidad, colores únicos para toda la UI, popup de la línea, Trouble |
| UI | lualine, tema gruvbox ↔ claro **o heredado de la terminal en vivo** (Alacritty), dashboard con arte braille, render-markdown, colores en línea |
| Sesiones | una por carpeta y rama, autoguardado periódico |
| **Go sin LLM** | ayudas de completado que leen tu código y tu `go.mod` (ver abajo) |
| **Agente de IA** (opcional) | `<leader>a`: de un disparo sobre la función bajo el cursor, con diff en línea (ver abajo) |

### Commits (`<leader>G`)

Un **panel único** para commitear: qué entra (preparado vs no preparado, con +/− por archivo), el mensaje con **validación en vivo de
Conventional Commits** (`✔ feat(scope) · 38/72`), tipo y scope asistidos y una línea que dice qué hará el agente *antes* de gastar nada.
`Gc` abre el panel, `Gm` lo abre con el borrador de la IA, **`GM` commitea solo, en segundo plano** (prepara lo modificado salvo lo sensible,
la IA escribe UN mensaje en inglés, se valida y se commitea; si algo falla, deshace lo que preparó) y `Ga` reescribe el último. El mensaje de la
IA sale siempre en inglés, en una línea, en ~2 s con un modelo ligero.

### Agente de IA (`<leader>a`)

No es un plugin: es código Lua de esta config, sin dependencias, y no hace nada hasta que lo invocas. Claude Code, OpenCode, **Ollama (CPU/CUDA)**,
LM Studio/llama.cpp/vLLM y otros CLIs; detecta y configura sus backends solo (`<leader>am` → Setup, o `./scripts/agent-setup.sh`).
Un menú corto genérico y un menú por **nivel**, cada uno con su carpeta y sus acciones:

| Menú | Qué hace |
|---|---|
| `<leader>a` | implementar, revisar, explicar, preguntar, documentar, refactorizar, entregar a Herdr; **`f` fix inline** (el diagnóstico de la línea, con el tipo de lo que señala) y **`F` fix de bloque** (la función entera) |
| `aT` **pruebas** | `w` escribe solo las pruebas que faltan al final del archivo de pruebas · `m` mock · `f` arregla una prueba corriéndola antes (si ya pasa, 0 tokens) · `g` huecos (local) |
| `aL` **lentes** | seguridad, rendimiento, concurrencia, errores, compatibilidad de API: revisiones de un solo foco como diagnósticos; cada una descarta antes lo que no le toca |
| `aD` / `aP` / `aS` | arquitectura hexagonal: dominio, repositorios y servicios, con análisis local de 0 tokens |

Además: limpiar hallazgos de uno en uno, por archivo o todos (`<leader>ac`, `aC`, `:AgentClear`), historial con prompt, respuesta, tokens y coste
(`<leader>ah`), modelos por tier (barato donde basta). Detalle en [docs/cheatsheets/agent.md](docs/cheatsheets/agent.md).

### Go sin LLM (completado inteligente, 0 tokens)

Sobre un índice compartido (`utils/goindex.lua`: treesitter + `go.mod`, en caché por fecha):

- **métodos que faltan** para cumplir una interfaz, con la firma exacta y cuerpos que llaman a tu dependencia (`return s.repo.FindByID(ctx, id)`);
- **`if err != nil`** con los valores cero de los retornos de la función y un mensaje sacado de lo llamado (el menú se abre solo tras `x, err := …`);
- **mapeadores** entre capas (`NoteResponse` ↔ `Note`), **cableado de constructores** (`NewNoteService(noteRepo)` con los argumentos resueltos),
  **helpers de un enum** (`IsValid`, `Parse`, `UnmarshalText`…), **interfaz desde un struct** y `var _ I = (*T)(nil)`,
  **handlers HTTP** desde un servicio (net/http, chi, gin, echo);
- tags de struct, constructores, literales rellenos, errores centinela, snippets de sentencias. Detalle en [docs/cheatsheets/go.md](docs/cheatsheets/go.md).

## Personalizar

Todo lo configurable está en `nvim/lua/core/settings.lua` con su valor por defecto y un comentario. Tus cambios van en
`nvim/lua/local.lua` (ignorado por git, se mezcla encima; el instalador puede generarlo con `--lang`, `--theme`, `--light`):

```lua
-- nvim/lua/local.lua
return {
  theme = { name = "catppuccin" },
  languages = { disabled = { "astro", "dart", "java", "kotlin" } },
  agent = { backend = "ollama", tiers = { lens_security = "light" } },
  git = { commit = { subject_max = 60 } },
}
```

Para añadir (cada cosa es **un archivo** y, a lo sumo, un nombre en su lista `NAMES`):

- **un lenguaje**: `nvim/lua/languages/<nombre>.lua` (contrato al inicio de `languages/init.lua`);
- **un plugin**: un archivo en `nvim/lua/plugins/<grupo>/`;
- **un arte de dashboard**: `nvim/lua/ui/arts/<nombre>.lua` (solo braille);
- **un backend de IA**: una entrada en `agent.custom` (sin código) o `nvim/lua/agent/backends/<nombre>.lua`;
- **una acción, lente o prueba del agente**: `agent/actions/`, `agent/lenses/actions/` o `agent/tests/actions/`;
- **una convención de pruebas por lenguaje**: `agent/tests/convention.lua`;
- **una ayuda de completado de Go**: un módulo `utils/go<nombre>.lua` sobre `goindex` y su llamada en `gosmart`.

## Cómo está organizado

Los principios (los mismos en todo el repo) y dónde se ven:

- **Una responsabilidad por módulo**: lo puro (`commit/conventional.lua`, `utils/goindex.lua`, `agent/protocol.lua`) separado de lo que toca
  git, el LSP o la UI (`commit/git.lua`, `commit/panel.lua`); un presentador por tipo de salida (`agent/output/`).
- **Abierto a extensión, cerrado a modificación**: registros descubiertos (`languages/`, `agent/actions/`, `agent/backends/`, `agent/lenses/`);
  añadir uno no obliga a editar los demás. El pipeline del agente se extiende con ganchos de acción (`retarget`, `merge`, `reveal`, `prepare`).
- **Dependencias hacia abstracciones**: cada pieza habla con un contrato pequeño (`build`/`parser` de un backend, `collect(target, done)` de un
  proveedor de contexto, `declaration_items(range, frag)` de una ayuda de Go), no con la implementación del vecino.
- **Lo configurable, en un solo sitio**: `core/settings.lua`; los scripts (`install.sh`, `install.ps1`) comparten la misma lógica de ajustes
  (`scripts/install-local.lua`) en vez de duplicarla.

## Teclas y documentación

- [`CHEATSHEET.md`](CHEATSHEET.md): **todas** las teclas. Se genera de los keymaps reales (`scripts/gen-cheatsheet.sh`; el hook de pre-commit lo regenera). Dentro de nvim, el botón *Mappings* del dashboard muestra lo mismo.
- [`docs/cheatsheets/`](docs/cheatsheets/README.md): lo que el código no dice (flujos, herramientas, trampas), una página por lenguaje y la del agente.
- [`AGENTS.md`](AGENTS.md) / [`CLAUDE.md`](CLAUDE.md): arquitectura y trampas para quien toque la config (personas o agentes).

## Estructura

```
install.sh · install.ps1      instalación (Linux/WSL/macOS · Windows)
VERSION                       versión de la config
nvim/                         la config (lo que se enlaza)
  init.lua                    solo bootstrap
  lua/core/                   ajustes, opciones, keymaps y autocmds de arranque
  lua/languages/              un archivo por lenguaje (se declara; no se cablea)
  lua/plugins/<grupo>/        un spec de lazy por plugin
  lua/menus/                  menús contextuales del leader
  lua/agent/                  agente de IA: backends, actions, context, output, tests, lenses, ddd, setup
  lua/commit/                 commits: validación (pura), git, borrador de IA, panel
  lua/utils/                  utilidades; go*.lua = ayudas de completado de Go sobre goindex
  lua/ui/ appearance/ themes/ dashboard, tema, colores
  snippets/ ftdetect/ syntax/ snippets y tipos de archivo propios
scripts/                      instalación (install-*.lua), cheatsheet, setup del agente y pruebas
docs/cheatsheets/             documentación por lenguaje y agente
.githooks/                    cheatsheet al día + Conventional Commits
```

## Mantenimiento

- Actualizar: `git pull` (la config se recarga sola al abrir nvim) y `:Lazy sync` si cambian plugins (o `./install.sh`).
- Comprobar: `scripts/test.sh` corre todo (agente y commits, ayudas de Go, instalador y cheatsheet al día; sin red ni tokens); cada suite
  también se corre sola: `scripts/test-agent.sh`, `scripts/test-go.sh`, `scripts/test-install.sh`, `scripts/gen-cheatsheet.sh --check`.
- Commits: formato Conventional Commits (`feat(scope): asunto`); el hook `commit-msg` lo valida y `<leader>Gc` / `Gm` / `GM` lo asisten.
