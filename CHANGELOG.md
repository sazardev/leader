# Changelog

All notable changes, newest first. Generated from the Conventional Commits since each tag (<leader>GRc).

## [1.20.0] - 2026-11-12

### Highlights

- **Go tests inside the editor**: `<leader>g` runs the test under the cursor (`M`), the file's package (`l`) or the whole module (`m`/`R`/`c`) through `go test -json`; marks on each test, failures as diagnostics and in the quickfix, and a statusline chip (`test ✓12 ✗1`) that stays red until the next run passes. `O` shows the runner's output. This is separate from `go build`, which never compiles `_test.go` files.
- **GoHawk**: ownership, lifecycle and concurrency checks from [GoHawk](https://gohawk.dev) through nvim-lint (only when the binary is installed), defects as errors and hazards as warnings, with the evidence in the float; `<leader>gH` audits the whole module. `settings.go.gohawk`.
- **A local completion model for this PC**: `<leader>Sm` / `:Fim model` detects the devices llama.cpp can use and recommends 0.5B CPU on an iGPU and 1.5B/3B/7B Q8 by dedicated-GPU VRAM, saves the choice and restarts the server. `settings.fim.model` takes a GGUF path or a `{ repo, file }` pair, and `gpu_layers = 0` keeps it on the CPU.
- **Chat navigation**: `PageUp`/`PageDown` jump between the messages you sent (centered), from the transcript or the composer, and your turns get a stronger blue bubble.
- **Installer**: the web installer verifies the desktop package by default.

### Features

- **go:** run tests in the editor with live status (3c29496)
- **go:** run every test action verbose by default (a7a911b)
- **go:** add GoHawk ownership and concurrency analysis (bfd152e)
- **fim:** pick the best local model for this PC (8c9dc61)
- **fim:** support a custom GGUF and CPU-only inference (8bc7b09)
- **chat:** jump between your messages with PageUp/PageDown (72a2839)

### Fixes

- **fim:** honor the injected local-model check (fda1889)
- **install:** verify the desktop package by default in the web installer (f44fa3c)

### Other changes

- docs: regenerate for the local model picker (f48b969)
- chore(deps): update schemastore.nvim (67a9d57)
- chore(packaging): point the Arch packages at v1.19.1 (86d9447)

## [1.19.1] - 2026-11-11

### Highlights

- **Installer fix**: 1.19.0 was tagged but not published because its package rejected modern glibc when `ldd | head` hit SIGPIPE under `pipefail`; 1.19.1 parses the version with `sed`. It is the first public build of the 1.19 workspace.

### Fixes

- **packaging:** parse modern glibc without a pipefail false positive (6d08eca)

## [1.19.0] - 2026-11-11

### Highlights

- **A Zed-like workspace**: quick open (`Ctrl+Shift+F`), the file tree (`Ctrl+Shift+E`), the chat/agent dock (`Ctrl+Shift+A`), the panes menu (`Ctrl+Shift+L`), the terminal pane (`Ctrl+Shift+J`) and focus mode (`Ctrl+Alt+Z`). The window shortcuts are configurable in `gui.shortcuts` and work while typing; View > Workspace, the toolbar and the command palette carry the same actions.
- **The GUI catches up with Leader**: a Chat menu with model, profile, effort, view, apply, context, thinking, tokens, stop and clear; an instant agent menu (models load only when picked); tree/chat/panes/focus tools with live active states; settings for bar height, controls, padding, activity, chat width and view.
- **Faster and cleaner**: the agent menu no longer waits for every backend (~0.4 ms instead of up to 800 ms each), the chat opens in ~24 ms, focus mode hides the app bar and statusline without system decorations, and the setup stays usable in short windows.
- **Signed releases again**: 1.19 is the first signed release after the 1.15-1.18 gap, with a new Leader Releases key (fingerprint `1982245F766BD77FBA36A8E73DAE20054C308EB6`). The previous key is retired; the 1.15-1.18 assets stay unsigned.
- **Site and community**: the documentation and offline guide in Help, the new website with short install links, and the project health files.

### Features

- **gui:** add the workspace, configurable shortcuts and chat options (39c536b)
- **gui:** documentation and offline guide in Help (370ebd4)
- **community:** health files, CI, banner and an offline guide (ec74422)
- **site:** deploy leader.sazardev.stream with SEO and short links (77a3568)

### Fixes

- **gui:** keep the setup usable in short windows and sessions clean (588dff1)
- **site:** serve the offline guide at /offline (bcb5e67)

### Other changes

- chore(packaging): rotate the Leader Releases signing key for 1.19.0 (c6d818d)
- docs(gui): document the workspace, shortcuts, panes and chat options (cbbe3ca)
- test(gui): cover workspace shortcuts, focus mode and short setups (3abf9ed)
- chore(deps): bump tokio from 1.54.0 to 1.54.1 in /app (#3) (eb8b2f8)
- chore(deps): bump smol_str from 0.3.6 to 0.3.7 in /app in the cargo group (#2) (c79609e)
- chore(ci): bump actions/checkout from 5 to 7 (#1) (cfe04fc)
- docs: link the live offline guide, not the raw file (4118f8f)
- docs(readme): mention Help > Offline Guide (26f74c6)
- docs(readme): link the FAQ and tidy the authors (4b35143)
- chore(ci): checkout v5 for the Node 24 runner (b463d0e)
- docs(readme): a clearer first screen with install and why (76a802a)
- chore(packaging): point the source Arch package at v1.18.0 (bd95fc7)

## [1.18.0] - 2026-11-11

### Highlights

- **Completion from a local model**: FIM ghost text from **Qwen2.5-Coder 1.5B Q8** served by **llama.cpp** on
  `127.0.0.1:8012`, off by default. `Ctrl+Tab` accepts a suggestion and `Ctrl+Shift+Tab` its first line in any insert
  buffer (chat and modals included); `Tab` stays blink.cmp's. The server starts on demand and sleeps when idle;
  `<leader>SF`, `:Fim` and the settings panel toggle it, and the statusline shows `FIM…`/`FIM`.
- **Sessions come back on their own**: a bare `leader` inside a project (or `leader <folder>`) restores its windows,
  files and terminals **before** the start screen would open, sourcing the file directly (no plugin load, no `git`
  subprocess). A file argument leaves that session alone, filetypes are matched again for treesitter and LSP, and open
  terminals return as fresh shells in the same place. `terminal` is in `sessionoptions`; `<leader>Pq`/`<leader>Q` quit
  everything asking first.
- **Panes you can lay out**: `<leader>V2`/`V3`/`Vm`/`V4` build two columns, three columns, a wide main pane with two
  stacked on the right and a 2x2 grid, keeping the file you edit in the first pane. `<leader>VX` closes every other
  pane, and `Alt+T` opens a quiet terminal pane below the current one whose shell survives `Esc`.
- **A quieter Markdown**: `*.md`/`*.mdx` open as normal editable buffers (no locked reading mode, no conceal) and
  render-markdown is off by default; `<leader>mr` renders one buffer, and the agent transcript and history preview keep
  rendering on demand.
- **The app's type**: `gui.font_weight` (400/500/600) and `linespace` give the desktop app the weight and the air
  between lines it was missing, both applied live; the default editor font is now `h13`.

### Features

- **markdown:** open plain and render on demand (6f8c316)
- **app:** font weight and line spacing (aa50f45)
- **fim:** local completion through llama.cpp (9305805)
- **panes:** layout presets and a quick terminal pane (887da2b)
- **sessions:** restore a bare start and keep terminals (6d09c5e)

### Other changes

- style(test): align the prefs test with the house style (4e6d21b)
- chore(deps): add llama.vim and bump schemastore and ui (81f8843)
- docs: FIM completion, session restore, panes and fonts (7e8b6fb)
- chore(packaging): point the source Arch package at v1.17.0 (d375f5d)

## [1.17.0] - 2026-11-10

### Highlights

- **Panes, like an IDE**: `Alt+V` / `Alt+H` open a real Neovim split with the **start screen** in it; `ff`/`fo` load the
  chosen file in that pane, and every pane keeps its own dashboard (selection, layout and window options). `Ctrl+h/j/k/l`
  moves, `Alt+arrows` resizes, `Alt+Z` zooms, `Alt+Q` closes, and `<leader>V` lists the panes plus equal sizes, rotate and
  swap. The old terminal splits moved to `<leader>Tv` / `<leader>Th` (the float stays on `Alt+I`), and the settings panel
  gained a **Panes** group.
- **The chat is a real editor pane**: the panel is a right split that reflows the code beside it, Write answers apply
  their complete files, turns are animated and code blocks keep treesitter colors. The model can ask a decision with an
  `ask` block (a picker puts the answer in the composer), request missing files with `@need:` (injected once on the next
  turn), and typing while an answer streams queues the message instead of refusing it; dropped history is disclosed.

### Features

- **panes:** dashboard splits and pane management (bd06e48)
- **chat:** ask picker, @need context, queue (180e7b0)
- **chat:** split panel, apply files, animate turns (f51e6df)

### Other changes

- chore(deps): sync nvim-tree and schemastore in the lockfile (e881281)
- chore(deps): bump neoconf and schemastore (4223338)
- chore(packaging): point the source Arch package at v1.16.0 (ebaf9c5)

## [1.16.0] - 2026-11-10

### Highlights

- **GitHub lives in the editor now**: `<leader>Gh` (inside a repo) opens **gh-dash** (PRs and issues), **gh-observer**
  (the current PR's checks, live), **gh-enhance** (Actions runs and logs) and **gh-news** (notifications) in their own
  terminals. The first launch of a missing extension shows the exact `gh extension install …` command and installs and
  starts it after you confirm; `<leader>Ghs` is the checklist. **octo.nvim** adds PRs, issues and reviews inside Neovim
  (`Ghp`/`Ghi`/`Ghr`), with the core `gh` commands (`v`, `c`, `b`, `a`, `A`) next to them.
- **Remotes from the Git menu**: `GP` pushes (setting the upstream the first time), `Gu` pulls with `--ff-only` (a
  divergent branch is reported, never merged behind your back) and `GF` fetches every remote with `--prune`. They run in
  the integrated terminal, which keeps the focus, and `Esc` closes the window without stopping the command.
- **The chat has profiles and a home**: Zed-style **Ask** (read-only), **Write** (the full coding partner) and
  **Minimal** (terse), saved with each session; `<leader>aC` on a project with conversations opens its history, newest
  first, instead of a blank buffer.
- **Go runs the package you are in**: `run`/`build` run the current file's package in repos with several `main`s
  (root, `cmd/api`, `cmd/worker`…), and `<leader>gl` tests that package (`go test ./folder`, a `main` package with
  tests included) while `m`/`R`/`c` keep testing the whole module. Commands launched from the menus keep the cursor in
  the terminal.
- **Find**: a visual selection pre-fills **grug-far**'s search (`<leader>fr`), so replacing what you selected is one
  key away.

### Features

- chat profiles, GitHub menu and git remotes (e128fcc)
- **go:** run the current file's package and test it in place (80b707a)
- **find:** prefill grug-far search from visual selection (2a9616e)

### Fixes

- **github:** keep `<leader>G` intact outside repos (73a4ed9)

## [1.15.0] - 2026-11-09

### Highlights

- **The terminal stops surprising you**: `terminal.run` went through `:TermExec` string parsing, which cut every
  quoted path (`dotnet run --project '/a b/x.csproj'` arrived as `dotnet run --project`). It now uses toggleterm's
  Lua API, and `<leader>T` (show / list / new / stop) reopens terminals without re-sending anything into them.
- **C# grows up**: a Solution Explorer (`<leader>cLo`), saveable run configurations with Docker (`<leader>cGr`),
  a visual NuGet manager (`<leader>cx`), `requests.http` generated from `Program.cs` routes (`<leader>ch`) and a
  Noodle collection with its TUI (`<leader>cNo`).
- **Razor, XAML and Unity join the pack**: `.razor`/`.cshtml` (html LSP), `.xaml` (as XML) and Unity YAML files
  (`.unity`, `.prefab`, `.meta`) with `Assets/` root detection.

### Features

- **terminal:** <leader>T menu, named terminals, honest docs (6f9ee10)
- **csharp:** explorer, run configs, nuget, http file, noodle (014f9cf)
- **csharp:** razor, xaml and unity packs (88e8cff)
- **chat:** persistent backend-agnostic chat under Leader (e38aa2f)
- **setup:** langsetup all languages, sections, reconcile (56a0fa7)
- **find:** dev-mode search in current file (8ac279f)
- **leader:** leader is nvim in a terminal (d1e25bd)
- **skills:** add Skills manager (<leader>aK) (705a945)
- **env:** environment file kit per stack with check and AI loader (4cd29f6)
- **markdown:** auto locked reading mode for md and mdx (03ea13e)
- **find:** add <leader>fc for current file (35fa7fa)
- **languages:** C#/.NET pack and MDX as Markdown (1ba0993)
- **pacakge:** update (0b45ae3)

### Fixes

- **markdown:** no cursor highlight in locked reading mode (f25c6eb)
- **agent:** build survives slow, rate-limited OpenCode (e2b1e54)

### Other changes

- chore(deps): update pinned plugins (634b1ef)
- chore(packaging): point the Arch packages at v1.14.2 (a9dc10b)

## [1.14.2] - 2026-10-21

### Highlights

- **An empty file can be a right answer**: a build used to report a failure for every file the model left empty, including the ones
  that are correct that way (a Python `__init__.py`, a `.gitkeep`, `py.typed`, the requirements file of a project with no
  dependencies). It now does for those what it should: nothing.

### Fixes

- **build:** an empty __init__.py is not a failed answer (5ecfbb0)

## [1.14.1] - 2026-10-21

### Highlights

- **Checked against a real build**: a build of a small project with Claude Haiku (13 files, $0.03, under 3 minutes) did what the
  1.14.0 notes promise: it named its riskiest requirement, deferred the one SPEC.md left open and said why, ended `⚠ built · 3/4
  requirements have a test` instead of `✓`, and left a `.leader/` folder with nothing of the project in it. Two details came out
  of it and are fixed here: the plan review no longer calls a test that uses a fake or a temporary directory a "stand-in", and the
  builder's own wiring check is recorded under its name.

### Fixes

- **build:** tests are not stand-ins, name the wiring check (1ff9203)

## [1.14.0] - 2026-10-21

### Highlights

- **A build no longer calls itself done when it only compiles**: the closing line now says what is proven, e.g. `◐ built · 23 files ·
  checks pass · 5/17 requirements have a test · core without one: FR-16 · 2 placeholders`, and it is `✓` only when every requirement has a
  test and nothing is open. PROGRESS.md carries the same proof and what is open. A layer build (foundation, design, domain) reports the
  numbers but keeps `✓`; `kit.build.strict` makes an unproven build a failure.
- **A repair cannot delete your code quietly**: before a replan trashes files, the review lists what goes (lines, public types, tests, who
  still uses them) and asks, and the closing line counts the public declarations a build removed or the tests it made unproven.
- **Layers build on the code that is there**: a whole-project build used to plan from the documents and the ADRs' text only, so it wrote
  the code earlier builds had left a second time under other names (two ports, two controllers, hundreds of analyzer errors). It now sees
  the project's files and their API. A free check fails when a public type is declared in two files, Flutter projects run `flutter test`
  and Rust ones `cargo test`, and plans name their risks and what they defer, with a warning for stand-ins of core requirements.
- **`.leader/` in every project the builder touches**: how Leader worked there (how builds end, which checks fail, what a model costs,
  whether you accept a proposal) as counts, sizes, durations, costs and outcomes, for measuring and improving Leader from real use.
  **Offline: nothing is ever sent.** It is never your work: a schema is the only gate, so unknown fields are dropped, file names are salted
  hashes, and there is no code, prompt, answer, name or text. The folder documents itself, ignores itself in git, `<leader>aSl` shows the
  report, `LEADER_NO_DATA=1` turns it off, and deleting it clears everything.

### Features

- **build:** honest builds and a local .leader folder (1cb1c6e)

### Fixes

- **build:** skip examples in the duplicate check, hide custom models (bebfb1d)

### Documentation

- **build:** proof, loss gate, duplicates and the .leader folder (94a536e)

### Chores

- **deps:** update the plugin lockfile (3ab99c6)

## [1.13.0] - 2026-10-21

### Highlights

- **The agent is measured now, and a modest model gets help**: `make eval` runs 31 cases (Python, Go, JavaScript, Lua; fix, docs,
  refactor, review) through the real pipeline against any model, judged by code (does it parse, does a script that imports
  it still pass, did anything outside the target move, did it find the planted bug), never by another model. On the committed
  baselines Claude Haiku passes 100% of the single tries on the cases it was tuned on at roughly a tenth of Sonnet's cost
  per usable answer. Every model gets a capability profile (small, medium, strong): a smaller target limit, a second try
  with the reason when an answer does not parse, server-shaped output for Ollama and OpenAI, a chain of single steps for an
  instruction that is several things, and an optional cascade to the main model.
- **You are told what is going to happen, and can take it back**: the spinner carries the estimate, every proposal says
  whether anything checks it (`checked on accept (LSP)` or `unverified`), the statusline shows what the session has spent,
  `<leader>au` takes a whole run back across files (never what you edited since) and `<leader>aSbu` takes the last build
  back.
- **Less on the menu**: DDD, the repository/service/lens menus, the doctor, building a whole project and multi-file plans
  are experimental and stay hidden until `agent.experimental` (Settings → Agent) is on. Nothing was removed.
- **Review stops crying wolf**: it no longer reports a finding that says nothing is wrong, nor hypothetical misuse; on the
  eval, Haiku went from 82% to 100% on review without losing the real findings.

### Features

- **agent:** evals, capability profiles, trust layer, experimental flag (3777b62)

### Documentation

- **agent:** evals, profiles, trust layer and stability (4cef712)

## [1.12.2] - 2026-10-21

### Highlights

- **Your nvim now speaks Herdr**: [Herdr](https://herdr.dev) is the terminal workspace that runs the coding agents, and
  Leader talks to its CLI. `<leader>Wa` opens the breakdown of the workspace: one row per agent grouped by workspace (its
  state, the agent and where it is), the transcript of the one under the cursor and **why** Herdr thinks it is in that
  state (the rule that matched). It refreshes on its own, so what is on screen is the state now. `<leader>Ws` is the
  setup: it detects the binary, the version, the server and the agents' integrations, and installs what is missing
  (nothing without the button) — the installer does the same, and the start screen gets an **Agents** button when Herdr
  is there.
- **And Herdr sees what your nvim is doing**: nvim registers itself as an agent of the workspace and says what it is
  doing (`working` while the inline agent runs, `blocked` while a proposal waits for you, `idle` otherwise), so the
  Agents panel of Herdr shows it. It never takes the pane from a real agent that already owns it, and a headless nvim (a
  script, a test) does not register at all.

### Features

- **herdr:** the workspace of agents under <leader>W (135c337)

## [1.12.1] - 2026-10-21

### Highlights

- **The code search index builds ~3x sooner and no longer freezes the editor**: on a 4000-file TypeScript monorepo the
  first `<leader>fs` took 19-35 s with 12-22 s of blocked UI (stalls up to 1 s); it now takes 6-10 s with the UI blocked
  ~0.2 s. The files are read by up to 4 headless Neovims in parallel (`settings.search.workers`); the result is identical
  to reading them in the editor, which is still what happens for a few changed files or if a worker fails.
- **Typing is smoother**: `nvim-highlight-colors` repainted the window on every key while the completion menu was open;
  it now waits 60 ms. In a TSX file the per-key cost went from p95 8.8-9.8 ms to 6.1-7.5 ms (the frame budget is 16.6 ms).
- **Less memory in big projects**: Tailwind's server only starts where the project uses Tailwind (~210 MB less in the API
  of a monorepo), TypeScript is linted by the eslint server alone (`eslint_d` stays for light mode), and a server that
  outgrows `settings.lsp.memory_limit_mb` (vtsls: 2200 MB; it reached 2.9 GB in a long session) is restarted when you are
  idle. `scripts/bench-project.lua` measures all of this on any project.

### Performance

- **lsp:** fewer resident servers, and tsserver cannot grow forever (44a781a)
- **ui:** highlight-colors repaints behind a 60 ms debounce (d1d39ba)
- **search:** the code index is built by parallel workers (08ddc7e)

### Other changes

- chore(bench): a probe for a real project (5aa2719)
- chore(packaging): point the PKGBUILDs at v1.12.0 (3995f15)

## [1.12.0] - 2026-10-20

### Highlights

- **Lua answers across files ~2.5x sooner**: Lua now uses `emmylua_ls` (a Rust server) when it is installed, and `lua_ls`
  otherwise. On this repo's 670 files cross-file go-to-definition worked at ~0.7 s against ~3.8 s on the bare workspace,
  and ~2.5x sooner with the full config, with the same hover, completion and diagnostics. `lua_ls` keeps nothing between
  sessions and its `maxPreload` has no effect, so the way to speed it up was a faster server. Mason installs it with the
  rest; `settings.lsp.lua_server` forces either one.
- **`<leader>dr` runs and stops a Flutter app**: pressed again while the app runs, it quits it and closes the debugger and
  every panel that opened, instead of only saying it is already running.
- **Your sessions are safe from tests**: Neovim saves a session on every exit, and a headless test that opened temp files
  in a repo replaced that folder's real session with files that no longer existed, so restoring the project opened an empty
  buffer. Persistence now stays off without a UI, every test script runs against a throwaway state directory, and the whole
  suite leaves sessions, recent files, agent history and logs byte-identical.

### Features

- **dart:** leader dr toggles run/stop (fffd15c)

### Fixes

- **sessions:** tests and headless runs never write your state (db55542)

### Performance

- **lsp:** Lua gets emmylua_ls when it is installed (~2.5x faster) (ccc1a54)

## [1.11.0] - 2026-10-20

### Highlights

- **Big files stay fast**: past 1.5 MB (or a minified bundle) a file opens as plain text, with no treesitter, LSP, folds,
  lint or formatter. A 4 MB Lua file opens in ~135 ms instead of ~1.9 s, and its first frame in the window matches a
  one-line file's.
- **Saving never freezes**: a buffer over 3000 lines is written at once and formatted in the background. A 15k-line save
  goes from ~1.2 s to ~20 ms. Linting is debounced, so a burst of Esc and saves lints once.
- **Stop a language server that takes too long**: `<leader>L` stops the servers of a buffer (also in the middle of
  "Loading workspace", in ~13 ms), stops all of them, restarts them, pauses everything, or says what is loading. A server
  that has not answered yet is found too. The editor cannot cache a server's workspace load, so this is the way out.
- **Code search remembers**: the index is kept on disk, so only the very first search parses every file (~5 s here);
  every later session loads it in ~120 ms. The first `<leader>ff` of a session is ~2x faster too.
- **A cleaner, faster start**: the window opens on the themed editor, never on a black frame, and the real editor reaches
  the screen ~45 ms sooner (graphics driver and Neovim start in parallel with the window, the first frame is warmed).
- **`leader --reuse file`** opens files in the window that is already running in ~6 ms, without a new window or Neovim.
  Opt-in; a plain `leader` is unchanged.
- **Measure it yourself**: `make bench` (startup, first frame, big files, picker, search index) and `make bench-edit`
  (big paste, undo, save, diagnostics, typing latency), with the findings and limits in `AGENTS.md`.

### Features

- **lsp:** stop, restart and pause language servers (<leader>L) (ecaf792)
- **gui:** a full-screen theme picker (0770236)

### Performance

- **app:** a faster, cleaner start and a window you can reuse (21d5427)
- **editor:** big files, saves, lint, search index, picker preload (c185df4)

### Other changes

- chore(bench): make bench and make bench-edit, and what they found (859c6b9)
- chore(dev): a Makefile and a real-time loop for the app (09ebf01)
- chore(packaging): point the PKGBUILDs at v1.10.0 (5b5cf42)

## [1.10.0] - 2026-10-20

### Highlights

- **Install it the way your system expects**: a `.deb` for Debian, Ubuntu, Mint and Pop!_OS, PKGBUILDs for Arch and CachyOS
  (prebuilt and from source), the one-command installer for any Linux and WSL, and `./install.sh --app` from a clone. They
  add the menu entry, the icons, the manual (`man leader`) and `leader-setup`, and uninstalling removes exactly what was
  installed.
- **Signed releases**: every file has a SHA-256 and a detached signature by the *Leader Releases* key (fingerprint in
  `packaging/README.md`). The installer requires a signature made by exactly that key when `gpg` is installed, and refuses
  a forged or missing one.
- **The logo, clear**: the N is the window icon, the menu icon at every size (a solid N when small, the dotted one when
  large) and the art of the About dialog. The app id is `io.github.sazardev.Leader`, so launchers pair the window with
  its icon and menu entry.
- **First launch that explains itself**: no Neovim says so in a notification; no Neovim config runs `leader-setup` in the
  window's own terminal. AppStream metadata, a New Window action, a license (MIT) and a site with Open Graph cards,
  structured data, a sitemap and real screenshots.

### Features

- **site:** SEO, screenshots, install options for every system (eab5dbc)
- **packaging:** signed releases, a .deb and Arch PKGBUILDs (3ebec37)
- **app:** the logo everywhere, an app id, first-launch setup (035cbea)

## [1.9.0] - 2026-10-20

### Highlights

- **Projects first, like an IDE**: Leader asks which project to open when it starts (or reopens the last one, or shows the
  start screen: your choice), `leader <folder>` opens that folder, and starting inside a repo opens that repo. The picker
  keeps its facts and the list it found on disk, reads git in the background one folder at a time, pins projects (`p`),
  and a Yazi-like browser (`b`: `h` up, `l` in, `Enter` opens) walks your folders.
- **Updates, connected**: a `↑ 1.9.0` badge in the bar and a line at the top of the logo's menu when a newer version
  exists; a page shows what changed version by version and updates on request (the config with `git pull --ff-only`, the
  app through its installer). One tiny request, never more often than every 12 hours, never updates by itself.
- **Recent files that belong to the project** you are in, not everything you ever opened (`Ctrl+A` widens it).
- **Esc closes whatever is extra**: help, quickfix, panels, floats, pickers (from insert too), lone tabs; never the last
  window. The hidden cursor has one owner list now, so it can no longer stay invisible after pages overlap.
- **Install progress in numbers**: every language tool with its state, time, bytes and speed, a bar, and a warning
  when data stops arriving. The window remembers its size, place and maximized state; the frame is yours to pick.
- **Speed**: hovering never scrolls a list, hovers are coalesced, Telescope no longer leaks a buffer per open, streaming
  answers redraw at most every 40 ms, and a list that fails to open leaves nothing behind.

### Features

- **gui:** projects first, a folder browser, install progress, Esc (e9ccc65)
- **app:** keep the window's size, place and maximized state (fd876ef)
- **ui:** one owner list for the hidden cursor, Esc closes extra windows (0157e10)
- **update:** detect new versions, show the changelog, update on request (3eac257)
- **recent:** recent files that belong to the project you are in (9ac6d49)

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

