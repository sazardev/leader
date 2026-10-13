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
| [agent.md](agent.md) | **Agente inline** (`<leader>a`): implementar/revisar/explicar... de un disparo con Claude u OpenCode |
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
`<leader>G` (Git) solo dentro de un repo, y `<leader>P` (sesiones), `<leader>S` (tema) y `<leader>C` (comentarios) son globales.
Pulsa `<leader>` y which-key muestra únicamente lo que aplica al archivo actual (sin delay).

Los menús de lenguaje abren una terminal integrada (toggleterm) y corren los comandos en la **raíz del proyecto**
(detectan `go.mod`, `package.json`, `Cargo.toml`, `pubspec.yaml`, `pom.xml`/`build.gradle`...).

## Flujos que conviene conocer

Las teclas exactas están en [`CHEATSHEET.md`](../../CHEATSHEET.md); aquí, cómo se combinan.

- **Saltar y volver**: tras `gd` / `grr` / `Ctrl+click`, `Esc` vuelve a donde estabas (si no editaste ahí); además cierra popups y quita el resaltado. `Ctrl+o` / `Ctrl+i` recorren el historial de saltos.
- **Diagnóstico de la línea** (`<leader>xd`): abre un popup; púlsalo otra vez para entrar y copiar el texto.
- **Diagnósticos en bloques** (`utils/diagblocks.lua`): `<leader>xa` los pinta todos bajo su línea (barra del color de la severidad, fuente/código y contador `2/5`); `<leader>xc` alterna entre todos desplegados y uno por uno (cada uno una línea, solo se abre el de la línea del cursor); `<leader>xn`/`xp` saltan al siguiente/anterior y encienden la vista en modo uno por uno. Salen solos en cada buffer con diagnósticos (el texto a la derecha, `virtual_text`, está apagado) y `<leader>xa` los apaga en ese buffer; entonces queda solo un icono de color (`✖ ▲ ● ○`, el de la severidad más alta) al final de la línea. **Gutter**: sin iconos junto al número. El FONDO del número se tiñe con la severidad más alta de la línea (rojo error, amarillo aviso, azul info, cian pista) y el git es una barra fina `┃` en la signcolumn (verde añadido, azul cambiado, rojo borrado), así no se confunden. Tu elección (`<leader>xa` encendido/apagado, `<leader>xc` desplegado/colapsado) es global y se guarda en `stdpath("state")/diagblocks.json`, así que vuelve igual al reabrir nvim; `settings.diagnostic_blocks` (`auto`, `mode`, `marker`) solo da el valor inicial. `<leader>xn`/`xp` con la vista apagada la encienden solo en ese buffer y no tocan lo guardado. Se actualiza solo al cambiar diagnósticos o cursor. El panel de abajo (`<leader>xx`, Trouble) entra con foco: `Enter` salta al diagnóstico y abre su popup, como `<leader>xd`.
- **Borrar sin pisar el portapapeles**: `<leader>d` + movimiento (`<leader>dd` línea, `<leader>dw` palabra) o en visual.
- **Multicursor** (`multicursor.nvim`, cursores reales como VS Code/Helix; se carga con la primera tecla): añade cursores por línea (`Ctrl+↑/↓`), por coincidencia de la palabra o selección (`Alt+n`/`Alt+p`, `Alt+Shift+n/p` salta una) o todas a la vez (`Alt+a`); `Alt+click` pone o quita uno con el ratón. Con varios cursores todo (motions, operadores, insert, undo) se repite en cada uno; `Esc` los limpia, `Ctrl+q` apaga/enciende el cursor principal, `←/→` cambian de cursor y `Alt+x` borra el actual. En insert, los cursores secundarios replican lo escrito AL SALIR de insert; si el menú de autocompletado está abierto, `Esc`/`jk` primero lo cierran y hace falta pulsarlos otra vez. Ideas: `Alt+a` sobre una palabra para renombrarla en el archivo; `Ctrl+↓` varias veces + `I`/`A` para editar columnas. El **bloque visual nativo** (`Ctrl+v` + `I`/`A`/`c`) sigue ahí para columnas simples. No uses `Ctrl+n` (es nvim-tree).
- **Textobjects** (treesitter): combínalos con operadores — `daf` borra la función, `dif` el cuerpo, `cif` lo cambia, `yaf` la copia, `vaf` la selecciona; `dac` borra la clase. Para llaves de cualquier bloque: `di{` (interior), `da{` (con llaves), `%` salta a la pareja. **PageDown/PageUp** saltan de bloque en bloque (función, método, clase, struct/interface en Go); no se detienen en closures dentro de una función, aceptan contador (`3<PageDown>`) y, sin bloques o sin parser, hacen el scroll normal. **Home/End** van al inicio/fin del bloque actual; pulsarlos otra vez sube al bloque que lo envuelve (método → clase → archivo). Para inicio/fin de línea usa `^`/`$` (o `0`), y en insert siguen siendo nativos.
- **Alt+hjkl** mueven línea o bloque (mini.move). La terminal horizontal de NvChad (`Alt+h`) se quitó para no pisarlo.
- **Formato**: `<leader>fm` formatea (conform); también se formatea al guardar.
- **Telescope**: el preview siempre es visible. Layout `flex`: a la derecha en ventanas ≥ 110 columnas, abajo en las angostas (`lua/plugins/navigation/telescope.lua`).
- **nvim-tree**: abrir un archivo cierra el árbol; `I` muestra/oculta lo ignorado por git. Borrar carpeta avisa cuántos archivos contiene.
- **Terminal**: `Esc` dentro de la terminal la cierra.
- **Autocompletado** (blink.cmp): la documentación aparece **al instante** al seleccionar y muestra, en los snippets, **lo que se va a insertar**. Nada viene preseleccionado, salvo dentro de un tag de struct de Go (ahí `Enter` acepta la primera sugerencia). Fuentes: LSP, path, snippets, buffer; en Go se suman `gotags` y `gosmart`; en Lua, `lazydev`.
  - **Con el menú abierto**, `Tab` / `Shift+Tab` eligen sugerencia (y `Enter` la inserta). **Sin menú**, dentro de un snippet (p. ej. `gorm.Open(dialector, opts)`), saltan al siguiente / anterior hueco.
  - **Quedarte con lo que escribiste y seguir**: `Esc` (cierra el menú sin salir del snippet) y luego `Tab`.
  - **`Esc` (o `jk`) con el menú abierto solo lo cierra** y deshace la sugerencia que estuviera insertada (vuelve a lo que tecleaste); sigues en insert y en tu snippet. Sin menú, salen de insert como siempre.
- **Sesiones**: una por carpeta (y por rama de git; `main`/`master` usan la base). No se restauran solas: botón **Restore Session** (`rs`) del dashboard o su tecla de menú. Abrir un solo archivo (`nvim x`) y salir sobrescribe la sesión de esa carpeta; hay una tecla para no guardar al salir.
- **Git**: git-blame está apagado por defecto (sin costo); se alterna desde el menú Git.
- **Commits convencionales** (`<leader>G`, un solo panel): `Gc` abre el panel, `Gm` lo abre y pide ya el borrador a la IA, `GM` commitea **solo, sin panel** (ver abajo), `Ga` reescribe el último commit (avisa si ya está en el remoto). Arriba ves **qué se commitea**: lo preparado (`●`, con +/− por archivo) y, aparte, lo que **no** entra (`○`, modificado o nuevo); `Espacio` prepara/quita el archivo (o todo el grupo si estás en su cabecera), `a` prepara todo, `u` quita todo, `p` o `Enter` muestran su diff. Abajo escribes el mensaje y el título lo **valida en vivo** (`✔ feat(scope) · 38/72`, o por qué falla); `Ctrl+t` elige el tipo (sugerido por los archivos) y `Ctrl+o` el scope (de las rutas y del historial). Debajo, una línea dice qué hará el agente **antes de gastar nada** (`✦ AI claude/haiku · ⌃g to draft · reads 2 files, 3.1k chars`: modelo ligero, solo lee lo preparado: su diff compacto sin lockfiles con tope `git.commit.diff_max_chars`, la rama y la lista de tipos) y, al terminar, qué hizo (`drafted by … · 2.5s · 1.2k→39 tok · $0.0001`); `Ctrl+g` pide el borrador (nunca solo, salvo con `Gm`), reemplaza el mensaje y se deshace con `u`, y repetirlo da otro. El mensaje sale **siempre en inglés y en una sola línea** (cabecera Conventional; ~2 s con haiku). **`GM` commit automático**: sin panel y en segundo plano; si ya preparaste archivos commitea solo esos, si no prepara todo lo modificado salvo lo sensible (`git.commit.sensitive`: `.env`, llaves…), la IA escribe el mensaje, se valida y se commitea, y un aviso de una línea dice hash, mensaje, archivos, +/−, tiempo y coste. Si algo falla (sin backend, IA, cabecera inválida, un hook) deshace lo que preparó y no deja nada a medias (`Gm` para hacerlo a mano). `Ctrl+s` (o `Enter` en normal) commitea; sin nada preparado o con un mensaje inválido avisa y no hace nada; si un hook rechaza el commit el panel sigue abierto para corregir. `Tab` alterna archivos ↔ mensaje, `q`/`Esc` cancelan (y paran al agente). El hook `.githooks/commit-msg` exige el mismo formato en cualquier `git commit` (tipos y largo en `git.commit`; si cambias la lista de tipos, cámbiala también en el hook).
- **Comentarios** (`<leader>C`): `Cd` inserta la plantilla de documentación idiomática de la función/tipo bajo el cursor (godoc, LuaCATS, JSDoc, docstring, rustdoc) con nombre, parámetros y retorno ya puestos; `Cm` lista en quickfix lo público que no tiene comentario de doc (para otros lenguajes usa el agente: `<leader>ad`). Snippets en cualquier lenguaje, con el comentario propio del lenguaje: `todo`, `fixme`, `note`, `hack`, `warn`, `perf`, `deprecated` (y con `o` al final, p. ej. `todoo`, `TODO(nombre):`); viven en `nvim/snippets/all.json`.
- **Tema**: gruvbox ↔ gruvbox_light, o heredar el de la terminal (Alacritty), que se sigue en vivo.
- **Otros**: `:TSContext toggle` fija el contexto de la función/clase arriba; `za`/`zc`/`zo` pliegan (folds por treesitter con nvim-ufo, todo abierto al iniciar); `<leader>C` pliega los comentarios largos (bloques o líneas `//` seguidas de `comments.min_lines` o más, 4 por defecto): `Cc` los pliega todos, `Ce` los despliega, `Ct` alterna el de bajo el cursor; con `comments.auto_collapse = true` los archivos se abren con ellos ya plegados; `:Lazy sync` instala/actualiza plugins (el auto-reload de la config no lo hace).

## Modo ligero

En equipos con ≤ 2 GB de RAM se apagan LSP, go.nvim y golangci-lint (queda `go vet`). Treesitter, conform y nvim-lint siguen.
Forzar con `NVIM_LIGHT=1|0`. Ajustes por máquina en `lua/local.lua` (ignorado por git).

## Añadir cosas

- **Lenguaje**: `lua/languages/<nombre>.lua` + agregarlo a `NAMES` en `languages/init.lua` + su página aquí.
- **Plugin**: un archivo en `lua/plugins/<grupo>/`.
- **Keymap nuevo**: ponle `desc` de **2+ palabras empezando por su sección** (`"Harpoon add file"`); el generador y NvCheatsheet agrupan por la primera palabra y descartan los de una sola.
- **Snippet de Go**: `nvim/snippets/go.json` (formato VSCode).
- Tras cambiar teclas o menús: nada que editar a mano; `scripts/gen-cheatsheet.sh` regenera `CHEATSHEET.md` (el hook `pre-commit` lo hace solo).
