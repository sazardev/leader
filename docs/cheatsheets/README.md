# Cheatsheets

> **Teclas: [`CHEATSHEET.md`](../../CHEATSHEET.md)** (raíz del repo) — la **única** fuente.
> Se **genera** leyendo los keymaps reales (`scripts/gen-cheatsheet.sh`) y se regenera en cada commit;
> no se edita a mano ni se duplican sus tablas aquí. Dentro de nvim, el botón **Mappings** del dashboard
> (`NvCheatsheet`) muestra lo mismo en vivo.
>
> Estas páginas guardan **lo que el código no dice**: qué hace cada cosa, flujos, herramientas, trampas.
> `<leader>` = `Space`.

| Chuleta | Qué cubre |
|---|---|
| [go.md](go.md) | **Go a fondo**: tags de struct, snippets, completado contextual, menú `<leader>g` |
| [typescript.md](typescript.md) | TypeScript / JavaScript / TSX |
| [python.md](python.md) | Python |
| [rust.md](rust.md) | Rust |
| [dart-flutter.md](dart-flutter.md) | Dart / Flutter |
| [java-kotlin.md](java-kotlin.md) | Java y Kotlin (Gradle / Maven) |
| [lua.md](lua.md) | Lua (la propia config) |
| [markdown.md](markdown.md) | Markdown |
| [web.md](web.md) | HTML, CSS, Tailwind, Astro |
| [data-formats.md](data-formats.md) | JSON, YAML, TOML, Docker, Prisma, YarnSpinner |

## Cómo funciona el leader

Cada lenguaje tiene **su propia letra** bajo `<leader>` y **solo existe en buffers de ese filetype**;
`<leader>G` (Git) solo dentro de un repo, y `<leader>P` (sesiones) y `<leader>S` (tema) son globales.
Pulsa `<leader>` y which-key muestra únicamente lo que aplica al archivo actual (sin delay).

Los menús de lenguaje abren una terminal integrada (toggleterm) y corren los comandos en la **raíz del proyecto**
(detectan `go.mod`, `package.json`, `Cargo.toml`, `pubspec.yaml`, `pom.xml`/`build.gradle`...).

## Flujos que conviene conocer

Las teclas exactas están en [`CHEATSHEET.md`](../../CHEATSHEET.md); aquí, cómo se combinan.

- **Saltar y volver**: tras `gd` / `grr` / `Ctrl+click`, `Esc` vuelve a donde estabas (si no editaste ahí); además cierra popups y quita el resaltado. `Ctrl+o` / `Ctrl+i` recorren el historial de saltos.
- **Diagnóstico de la línea** (`<leader>xd`): abre un popup; púlsalo otra vez para entrar y copiar el texto.
- **Borrar sin pisar el portapapeles**: `<leader>d` + movimiento (`<leader>dd` línea, `<leader>dw` palabra) o en visual.
- **Multicursor nativo** (`Ctrl+↓/↑`): abre un bloque visual y lo extiende línea a línea; luego `I`, `A`, `c` o `$A` escriben en todas las líneas.
- **Textobjects** (treesitter): combínalos con operadores — `daf` borra la función, `dif` el cuerpo, `cif` lo cambia, `yaf` la copia, `vaf` la selecciona; `dac` borra la clase. Para llaves de cualquier bloque: `di{` (interior), `da{` (con llaves), `%` salta a la pareja.
- **Alt+hjkl** mueven línea o bloque (mini.move). La terminal horizontal de NvChad (`Alt+h`) se quitó para no pisarlo.
- **Formato**: `<leader>fm` formatea (conform); también se formatea al guardar.
- **Telescope**: el preview siempre es visible. Layout `flex`: a la derecha en ventanas ≥ 110 columnas, abajo en las angostas (`lua/plugins/navigation/telescope.lua`).
- **nvim-tree**: abrir un archivo cierra el árbol; `I` muestra/oculta lo ignorado por git. Borrar carpeta avisa cuántos archivos contiene.
- **Terminal**: `Esc` dentro de la terminal la cierra.
- **Autocompletado** (blink.cmp): la documentación aparece **al instante** al seleccionar y muestra, en los snippets, **lo que se va a insertar**. Nada viene preseleccionado, salvo dentro de un tag de struct de Go (ahí `Enter` acepta la primera sugerencia). Fuentes: LSP, path, snippets, buffer; en Go se suman `gotags` y `gosmart`; en Lua, `lazydev`.
  - **Dentro de un snippet** (p. ej. `gorm.Open(dialector, opts)`), `Tab` **salta al siguiente hueco y cierra el menú**: lo que escribiste se queda tal cual. Para elegir una sugerencia ahí, `Ctrl+n` / `Ctrl+p`. Fuera de un snippet, `Tab` elige la siguiente sugerencia.
  - **`Esc` (o `jk`) con el menú abierto solo lo cierra** y deshace la sugerencia que estuviera insertada; sigues en insert y en tu snippet. Sin menú, salen de insert como siempre.
- **Sesiones**: una por carpeta (y por rama de git; `main`/`master` usan la base). No se restauran solas: botón **Restore Session** (`rs`) del dashboard o su tecla de menú. Abrir un solo archivo (`nvim x`) y salir sobrescribe la sesión de esa carpeta; hay una tecla para no guardar al salir.
- **Git**: git-blame está apagado por defecto (sin costo); se alterna desde el menú Git.
- **Tema**: gruvbox ↔ gruvbox_light, o heredar el de la terminal (Alacritty), que se sigue en vivo.
- **Otros**: `:TSContext toggle` fija el contexto de la función/clase arriba; `za`/`zc`/`zo` pliegan (folds por treesitter con nvim-ufo, todo abierto al iniciar); `:Lazy sync` instala/actualiza plugins (el auto-reload de la config no lo hace).

## Modo ligero

En equipos con ≤ 2 GB de RAM se apagan LSP, go.nvim y golangci-lint (queda `go vet`). Treesitter, conform y nvim-lint siguen.
Forzar con `NVIM_LIGHT=1|0`. Ajustes por máquina en `lua/local.lua` (ignorado por git).

## Añadir cosas

- **Lenguaje**: `lua/languages/<nombre>.lua` + agregarlo a `NAMES` en `languages/init.lua` + su página aquí.
- **Plugin**: un archivo en `lua/plugins/<grupo>/`.
- **Keymap nuevo**: ponle `desc` de **2+ palabras empezando por su sección** (`"Harpoon add file"`); el generador y NvCheatsheet agrupan por la primera palabra y descartan los de una sola.
- **Snippet de Go**: `nvim/snippets/go.json` (formato VSCode).
- Tras cambiar teclas o menús: nada que editar a mano; `scripts/gen-cheatsheet.sh` regenera `CHEATSHEET.md` (el hook `pre-commit` lo hace solo).
