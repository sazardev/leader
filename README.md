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
4. instala los plugins (lazy.nvim, versiones fijadas en `nvim/lazy-lock.json`), los LSP/formatters/linters (Mason) y
   compila los parsers de treesitter (`tree-sitter-cli` viene de Mason).

Después abre `nvim`. Pulsa `<Space>` y which-key te enseña los menús.

| Opción | Efecto |
|---|---|
| `-y` | sin preguntas |
| `--lang go,typescript` | solo esos lenguajes (+ lua): el resto se desactiva en `nvim/lua/local.lua`, así no se instala nada que no uses |
| `--no-deps` | no toca paquetes del sistema ni Neovim |
| `--no-plugins` | solo enlaza; plugins y herramientas se instalan solos la primera vez que abres nvim |
| `--dry-run` | muestra lo que haría |

Lenguajes disponibles: `lua go typescript html css tailwind json yaml toml markdown docker prisma astro dart rust python java kotlin yarnspinner`.

**Windows nativo** (PowerShell): `./install.ps1` crea el junction en `%LOCALAPPDATA%\nvim` y hace los mismos pasos 3 y 4.
(Escrito pero no probado en Windows real; en WSL usa `install.sh`.)

**Desinstalar**: borra el enlace `~/.config/nvim` (y, si quieres, `~/.local/share/nvim`, `~/.local/state/nvim`, `~/.cache/nvim`).

## Filosofía

- **Rápido**: arranque de ~25 ms (medido en headless, con `--startuptime`); `defaults.lazy = true`, plugins por evento/filetipo/comando/tecla, cache de bytecode (`vim.loader`) y plugins nativos innecesarios desactivados.
- **Mínimo**: 54 entradas en `lazy-lock.json`, **contando** dependencias y las del propio NvChad. Sin gestor de sesiones pesado, sin barra de tabs, sin chat de IA embebido, sin árbol de dependencias de LSP que no uses.
- **Modular**: la config se *declara*, no se cablea. Añadir un lenguaje o un plugin es crear un archivo; nada más se toca.
- **Ligero donde hace falta**: con ≤ 2 GB de RAM se apagan automáticamente los procesos residentes (LSP, golangci-lint); se fuerza con `NVIM_LIGHT=1|0`.
- **Todo con teclado**, teclas documentadas y generadas desde el código real.

## Qué incluye

| Área | Contenido |
|---|---|
| Lenguajes | Go, TypeScript/JS/TSX, HTML/CSS/Tailwind/Astro, Python, Rust, Dart/Flutter, Java/Kotlin, Lua, Markdown, JSON/YAML/TOML, Docker, Prisma, YarnSpinner. Cada uno declara su LSP, formatter, linter, parsers y su menú `<leader>` (solo existe en buffers de ese filetipo) |
| Edición | blink.cmp, mini.pairs/surround/move, multicursor, flash (saltos), textobjects de treesitter, folds (ufo), snippets propios (Go y generales) |
| Navegación | Telescope (+fzf), nvim-tree, harpoon, aerial (símbolos), grug-far (reemplazo global), historial de archivos |
| Git | gitsigns, diffview, git-conflict, git-blame (apagado por defecto), **commits convencionales** (asistente y mensaje con IA) |
| Diagnóstico | bloques en línea bajo su línea, popup de la línea, Trouble |
| UI | lualine, tema gruvbox ↔ claro **o heredado de la terminal en vivo** (Alacritty), dashboard con arte braille, render-markdown, colores en línea |
| Sesiones | una por carpeta y rama, autoguardado periódico |
| **Agente de IA** (opcional) | `<leader>a`: implementar, revisar, explicar, arreglar, documentar, escribir pruebas, revisiones de seguridad/rendimiento/concurrencia... de un disparo sobre la función bajo el cursor, con diff en línea; Claude Code, OpenCode, **Ollama (CPU/CUDA)**, LM Studio/llama.cpp/vLLM y otros CLIs. Detecta y configura sus backends solo (`<leader>am` → Setup, o `./scripts/agent-setup.sh`). Ver [docs/cheatsheets/agent.md](docs/cheatsheets/agent.md) |

El agente no es un plugin: es código Lua de esta config, sin dependencias, y no hace nada hasta que lo invocas.

## Personalizar

Todo lo configurable está en `nvim/lua/core/settings.lua` con su valor por defecto y un comentario. Tus cambios van en
`nvim/lua/local.lua` (ignorado por git, se mezcla encima):

```lua
-- nvim/lua/local.lua
return {
  theme = { name = "catppuccin" },
  languages = { disabled = { "astro", "dart", "java", "kotlin" } },
  agent = { backend = "ollama" },
}
```

Para añadir:

- **un lenguaje**: `nvim/lua/languages/<nombre>.lua` (contrato al inicio de `languages/init.lua`) y su nombre en `NAMES`;
- **un plugin**: un archivo en `nvim/lua/plugins/<grupo>/`;
- **un arte de dashboard**: `nvim/lua/ui/arts/<nombre>.lua` (solo braille);
- **un backend de IA**: una entrada en `agent.custom` (sin código) o `nvim/lua/agent/backends/<nombre>.lua`.

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
  lua/agent/                  agente de IA (backends, acciones, contexto, salida, setup)
  lua/ui/ appearance/ themes/ dashboard, tema, colores
  snippets/ ftdetect/ syntax/ snippets y tipos de archivo propios
scripts/                      cheatsheet, setup y pruebas del agente
docs/cheatsheets/             documentación por lenguaje y agente
.githooks/                    cheatsheet al día + Conventional Commits
```

## Mantenimiento

- Actualizar: `git pull` (la config se recarga sola al abrir nvim) y `:Lazy sync` si cambian plugins (o `./install.sh`).
- Comprobar: `scripts/gen-cheatsheet.sh --check` (cheatsheet al día) y `scripts/test-agent.sh` (agente; sin red ni tokens).
- Commits: formato Conventional Commits (`feat(scope): asunto`); el hook `commit-msg` lo valida y `<leader>Gc` / `<leader>Gm` lo asisten y `<leader>GM` commitea solo (mensaje de la IA en inglés).
