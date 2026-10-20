# Changelog

All notable changes, newest first. Generated from the Conventional Commits since each tag (<leader>GRc).

## [1.8.0] - 2026-10-20

### Highlights

- **Guided setup** in the desktop app: seven steps on one screen on the first launch (and with `Ctrl+Shift+W`). It shows
  what this machine is, lets you pick a theme previewed live, your languages (the ones you already use checked), a few
  features and an AI agent with its model, then lists what is missing with the exact command for your Linux family
  (pacman, apt, dnf, zypper, apk). Nothing runs until you press Install; sudo asks in a terminal and each item shows its
  status. A review with the install checks closes it.
- **A toolbar you decide**: a right click on the bar turns each tool and chip on or off (project, home, recent files,
  palette, file tree, terminal, problems, agent, theme, settings, setup). The theme and the agent are right there: a
  theme menu previewed as you hover, and every installed agent with its models. Every tool shows a tooltip with its key.

### Features

- **gui:** guided setup and a toolbar you decide (aef5599)
- **app:** a customizable toolbar with tooltips (a5b7db1)

### Other changes

- docs(gui): document the guided setup and the toolbar (48502be)

## [1.7.0] - 2026-10-19

### Highlights

- **Leader for the desktop** (Linux and WSL): `leader`, a GPU window for the editor written in Rust. The same config,
  drawn in one GPU draw call per frame, nothing running between keystrokes, ~170 ms to the first frame. Its own bar in the
  theme's colors: Zed-like menus (File, Edit, Selection, View, Go, Run, Git, Agent, Window, Help), a command palette
  (`Ctrl+Shift+P`), the projects you work in (switched with their sessions) and a full-screen project picker
  (`Ctrl+Shift+O`), the current file as a clickable path, live activity (LSP indexing, installs, saves). Full mouse:
  menus, pickers, modals, Telescope, the tree and the start screen follow the pointer and answer a click. A welcome
  screen checks the install and fixes what is missing. Install it in one command
  (`curl -fsSL https://github.com/sazardev/leader/releases/latest/download/leader-installer.sh | bash`: the app, plus
  Neovim and the config when they are missing; Linux x86_64 with glibc 2.31+, WSL with WSLg) or from a clone with
  `./install.sh --app`.
- **Doctor** (`<leader>aX`): a troubleshooting agent for builds that fail, apps that will not start or crash. Free
  checks first (dependencies, lockfile, `.env`, toolchain versions, a merge in progress), then one confirmed request.
- **Merge conflicts** (`<leader>Gx`): trivial ones resolved for free, the rest one proposal per conflict.
- **Language packs**: Python, TypeScript, Rust, SQL, Swift, JVM and more as packs, with tests in the editor, project
  setup presets, debugging and a SQL runner. The installer asks once which packs you want.
- **A full-screen marketplace** for SPEC.md modules and STACK.md / DESIGN.md add-ons, and a bigger library of each.
- **Leader** is the new name (repo `sazardev/leader`), with a brand kit, wallpapers and a scripted product video.

### Features

- **app:** release package with a guided installer (9cb78d4)
- **gui:** the config side of the desktop app (8c320ce)
- **app:** Leader desktop app, a GPU front-end for Neovim (f0ee3b0)
- **site:** wallpapers page, fed by a release of the brand assets (196b936)
- **brand:** logo, image catalog and wallpaper collection (602c5a7)
- **video:** scripted product video with keys, effects and score (9ec8b75)
- **agent:** doctor, a troubleshooting agent (4b23e52)
- **git:** merge conflict assistant (818657c)
- **kit:** full-screen marketplace and a bigger library (af08bb9)
- **agent:** statusline badge for one-shot requests (a2b18f9)
- **languages:** packs, tests in the editor, setup and SQL runner (4c6f2a1)
- **agent:** SPEC.md modules for what every app repeats (50e3da4)

### Fixes

- **kit:** drop a stray local path from the design presets (9ced0ca)

### Other changes

- docs(app): install and document the desktop app (fb4775e)
- chore(rename): rename my-nvim-setup to Leader (0a5425c)
- docs(agent): document the doctor, conflicts and marketplace (3a3e74a)
- docs(docs): list Go and Dart / Flutter under Languages (4270f1f)

## [1.6.0] - 2026-10-19

### Highlights

- **Build by layer** (`<leader>aSb` then `t`, `s` or `d`): the foundation from STACK.md, the domain from SPEC.md or the
  screens from DESIGN.md, each built on top of the files the project already has. `bb` still builds everything at once.
- **Build one feature** (`<leader>aSbf`): pick a requirement of SPEC.md, or describe a new one in your words; it is added
  to SPEC.md as the next FR-n (after a confirmation) and built end to end, following the patterns the code already uses.
- **Recipes** (`<leader>aSr`): twelve prefab tasks for your stack (a Flutter screen with its state, a data feature or a
  form; a Go endpoint, entity with its repository, CLI command or Bubble Tea screen; web components and pages; TypeScript,
  Python and Rust endpoints). Each is a plain Markdown file you can copy and adapt.
- **Coverage** (`<leader>aSv`, 0 tokens): which requirements have a test, what STACK.md names that the manifest lacks,
  DESIGN.md tokens no code uses, folders no document mentions.
- **Decisions and progress** (0 tokens): every accepted plan records its new decisions as ADRs in `docs/adr/`, which
  later builds follow (reversing one is explicit: `Supersedes ADR NNNN`); `PROGRESS.md` says what was done, what is
  open and what is next. `<leader>aSP` lists them.
- **Release kit** (`<leader>GR`): this changelog and the next version from the Conventional Commits (`c`), a pull request
  description (`p`, one light request, copied to the clipboard) and a release checklist from STACK.md (`l`). It never
  tags, pushes or posts.
- **Flutter**: run on a chosen device, profile mode, quieter runs. **opencode 2.x** CLI supported.

### Features

- **agent:** layer and feature builds, recipes, ADRs, release kit (b2644fd)
- **agent:** support the opencode 2.x CLI (790cf02)
- **dart:** run on a chosen device, profile mode, quiet runs (b109513)

### Fixes

- **release:** write other changes as the commit is written (8e93451)
- **commit:** force a/ b/ prefixes in the staged diff (e67396c)

### Other changes

- chore(deps): update neoconf.nvim and nvim-treesitter (5abb9eb)
- test(agent): keep the backend detection test hermetic (573dec0)

## [1.5.0] - 2026-10-18

### Features

- **agent:** build look step, design screens and toolkits, live plan (cb319cc)
- **agent:** project kit (<leader>aS) and build with agent (43fe81a)

## [1.4.0] - 2026-10-15

### Features

- **history:** undo word by word, redo keys, clipboard and yank list (8b7c617)
- **go:** getters, Reconstitute, repository port and package ranking (8df42c8)
- **dart:** tests in the editor, entry points, pub and translations (3b93295)
- **dart:** debugging, build_runner watch and stack completion (1e51b98)
- **agent:** convert selection, smaller context, Dart support (1c441fc)
- **setup:** .gitignore from the project and Go config presets (eb0b24a)

### Fixes

- **docs:** polish the docs site on phones and desktop (49838b4)
- **theme:** follow the terminal theme faithfully and live in every nvim (6b26a31)

### Performance

- **theme:** terminal theme starts as fast as the default one (7a060db)

### Other changes

- chore(deps): update schemastore.nvim (43b5e4d)
- docs: web documentation at /docs, generated from the Markdown (362660e)

## [1.3.0] - 2026-10-15

### Features

- **tasks:** run the targets of the project's Makefile from <leader>R (19d630d)
- **agent:** answer cache, next edit, diff-only docs and code search (47d3945)
- **diagnostics:** copy the line, the file or the project as text (2b6d1fd)
- **files:** create, rename, move, duplicate and delete from <leader>F (f6f0ecb)
- **settings:** a settings panel on <leader>S (217be6a)
- **folds:** fold code by what it is from the <leader>z menu (18863ae)
- **terminal:** Esc and Shift+Esc in NvChad terminals (7df03f4)

### Fixes

- **ui:** modal buttons, filled rows and floats without a dark hole (77549d5)

### Other changes

- chore(deps): update neoconf.nvim and schemastore.nvim (e131374)
- docs: settings panel, file operations, copy diagnostics and the tree (533f1df)

## [1.2.0] - 2026-10-14

### Features

- **agent:** agentic layer on top of the inline pipeline (68b0012)

### Performance

- **agent:** warm opencode server, no MCP or thinking, cheap model list (42e435e)

### Other changes

- docs(site): demo scenarios for the agentic layer (a841bfa)

## [1.1.0] - 2026-10-14

### Features

- **agent:** history in markdown with filters and back navigation (7391daf)
- **ui:** every view drawn like the landing page's demo (ee4615c)
- **ui:** which-key labels without the section the menu already says (377cd38)
- **ui:** commit panel bars, key hints as words, which-key grid (8dc4010)
- **ui:** start screen identical to the landing page's, compact popups (420d023)
- **ui:** optional key display like the demo's keycaps (:FlatKeys) (8b89b30)
- **ui:** flat design for the whole editor, same as the demo (1e4a33b)
- **install:** one-command install with bootstrap, no prompts (93b8bc4)
- **install:** ajustes por máquina y agente de IA desde el instalador (c3ca0f4)
- **comments:** plegado de comentarios con preferencia que se recuerda (3306c7a)
- **diagnostics:** colores unificados y número de línea con píldora (5c23cab)
- **go:** if err, mapeadores, cableado, enums, port y HTTP sin LLM (6a1eff6)
- **go:** completar los métodos que faltan para cumplir una interfaz (e5fe0d0)
- **agent:** pruebas (aT) y lentes (aL) con gasto mínimo de tokens (10dbc7d)
- **commit:** borrador de IA rápido y en inglés, y commit automático GM (ce388d1)
- **agent:** fix en dos niveles, en línea (af) y de bloque (aF) (e572dce)
- **agent:** limpiar hallazgos de uno en uno, por archivo o todos (f29532c)
- **commit:** panel único para commitear con validación e IA clara (e849ae6)

### Fixes

- **lsp:** servers never attach to diffview:// and other virtual buffers (5fd444f)
- **ui:** telescope preview hit line and text chips without patches (f92969b)
- **ui:** files opened from the start screen lost their line numbers (0c6b3d2)
- **install:** run the agent setup without loading the user config (26676ba)

### Other changes

- chore(plugins): update nvim-treesitter and schemastore (31da4dc)
- docs(site): agent scenarios drawn as Neovim draws them (204b017)
- docs(site): terminal-derived theme picker, menus from real keymaps (eaf2c98)
- docs(site): 41 demo scenarios in tabs: search, tree, replace, git, more (90d8974)
- docs(site): flat inspect floats, no border and no divider (b44dba3)
- docs(site): hover, signature help, diagnostics popup and completion docs (7147a7c)
- docs(site): faithful editor demo with multicursor, DDD and commit panel (9b8e9da)
- docs(site): scripted real-looking editor for the Go and agent demos (c1dd9db)
- docs(site): redesign the landing page flat, square and minimal (9a6e050)
- docs(site): single-file landing page in the config's own design (f56c5ea)
- chore: translate scripts, installers, hooks and tests to English (6aea6b9)
- refactor: translate code comments and UI text to English (1776927)
- docs: translate README, AGENTS, CLAUDE and cheatsheets to English (db1990f)
- docs(readme): README con todo lo nuevo y los principios de diseño (bb3faee)
- test(agent): más margen para gopls en frío en test-fix (ca8392d)
- refactor(go): gohttp separa lo de cada router y quita código muerto (e98ff23)

## [1.0.0] - 2026-10-13

### Features

- **install:** instalador de un paso para Linux, WSL, macOS y Windows (7d47d1f)
- **agent:** agente inline con DDD, niveles y modelos locales (9fa27fd)
- **editing:** commits convencionales, bloques de diagnóstico (3159950)
- **session:** autoguardado periódico y reapertura del pane en Herdr (7adaa22)
- **dependencies:** new (8a8ef31)
- **ui:** diagnósticos de la barra como etiquetas E/W de color y sin LSP (e74c296)
- **go:** atajos de archivos de modelo (functable, funcdomain, functodomain, funcfromdomain) (b969d7f)
- **go:** tags gorm con variantes por campo/tipo y TableName en *_model.go (d2aaefc)
- **docs:** cheatsheet único generado desde los keymaps reales (a5ea1a6)
- **docs:** new marketing slogan (4380500)
- **docs:** new marketing slogan (cb73724)
- **dashboard:** 66 arts braille nuevos (mascotas, anime, retro, comida) (3198ee1)
- **docs:** new marketing slogan (88e6e19)
- native search/autoread options, lazydev and git-conflict (7f14f7b)
- **git:** diffview (<leader>Gd/Gf/Gr/Gq) and treesitter-context (0ef25e4)
- **session:** persistence.nvim with dashboard Restore Session button and <leader>P menu (b16163d)
- **options:** jumpoptions=view, diagnostics severity_sort, restore last cursor position (63f7d5c)
- **markdown:** toggle diagnostics, reading mode, spell, word count, checkbox (d2665a9)
- **docs:** new marketing slogan (adf7b62)
- **design:** new ascii art for neovim! (1d899be)
- **dashboard:** add herdr braille art (da3d974)
- **dashboard:** braille art catalog discovered from lua/ui/arts, picker with "Change Art" (8b4657a)
- **keymaps:** native multicursor with Ctrl+Down/Up (visual block) (c854a30)
- **nav:** <Esc> goes back after gd/grr, <leader>H file history; fix <leader>q (8334e31)
- **lsp:** clear definition/references navigation (gd, grr, Ctrl+click) (413d00a)
- **terminal:** responsive integrated terminal panel for language menu actions (8efa087)
- **theme:** inherit the terminal (Alacritty) theme with live follow and <leader>S settings (c3e6412)
- **keymaps:** <leader>q closes buffer or quits nvim (a9d3dd1)
- **funcs:** new funcs (f063361)
- light mode, blink.cmp tab-complete, color previews; drop rest.nvim/lazygit (3e3622c)
- blink.cmp, harpoon, mini.move, drop sessions (98d62f5)

### Fixes

- **plugins:** go.nvim y flutter-tools respetan languages.disabled (30c4a40)
- **session:** registro de nvim como agente de Herdr apagado por defecto (e9d8327)
- **completion:** Tab vuelve a elegir sugerencia con el menú abierto; Esc + Tab para saltar (a983fb5)
- **completion:** Tab salta de hueco en snippets y Esc/jk solo cierran el menú (beb23dd)
- **dashboard:** usa layout horizontal en el picker de arte (7e16d09)
- **dashboard:** re-lock nvdash buffer after resize (NvChad leaves it modifiable) (b10b2cc)
- **telescope:** defer require until display closure (1d1b556)

### Other changes

- docs(readme): README nuevo con instalación, filosofía y estructura (c36b153)
- refactor(i18n): pasa a inglés los textos de UI (keymaps, menús, notificaciones) (8136b19)
- chore(lock): add persistence, diffview, treesitter-context and refresh plugin versions (fb79e18)
- docs: document sessions, diffview and treesitter-context in AGENTS.md (b49eae4)
- new art! (607c7ba)
- refactor: modular architecture, contextual leader menus, and config cleanup (f3f2dd1)
- refactor: trim unused plugins and keymaps, add global replace (73fb3d6)
- unify visual: single borders, zero icons, fix diagnostics (f1ebbad)
- docs for go! (e3719b4)
- Remove Copilot plugin and dependencies (5ceb0fa)
- Add Go tooling keymaps, fix treesitter highlighting, brighten gruvbox syntax colors (a8e5bb2)
- update config (c4f50b2)
- update config (81c1348)
- update config (2e53d5b)
- update config (b454716)
- update config (d9a5192)
- update config (1bd0135)
- update config (0227935)
- update config (dc6de83)
- update (33b096d)
- update chadrc (61586bd)
- update (53069e6)
- add AGENTS.md (f9a64be)
- update config files and README (7c45f1e)
- update config files (b4dba20)
- Initial commit (68e950e)
