# C# / .NET

Filetype: `cs`. Pack `csharp`.

## Tools

| What | With |
|---|---|
| LSP | **Roslyn** (Microsoft's official server, a global `dotnet tool`) when it is installed; **csharp-ls** (Mason) as the fallback |
| Format on save | `csharpier` (Mason, or the project's local tool) |
| Debug | `netcoredbg` (Mason): the assembly `dotnet build` produced |
| Tests | `dotnet test` with a TRX report, inside the editor (`langtest`, adapter `dotnet`) |
| Treesitter | `c_sharp` (plus `razor`, `xml`, `yaml` for the pack's markup) |
| SDK | `dotnet-sdk` (the runtime alone is not enough) |

The pack `csharp` now covers **Razor/Blazor** (`.razor`, `.cshtml` → `razor`), **XAML** (`.xaml` → `xaml`,
parsed as `xml`), and **Unity** (`.unity`/`.prefab`/`.meta`/… → `unity`, parsed as `yaml`, plus the
`Assets/` + `ProjectSettings/` root detection in `utils/csharpproj.lua`). The pre-Razor API-only projects
(like `tracking-system-amphenol`) are untouched: the new filetypes simply never appear there.

The server is chosen in `lua/servers/csharp.lua`: `auto` prefers Roslyn and falls back to csharp-ls, and the
settings panel (`<leader>Sp` → C# → Language server) can force either one (`settings.lsp.csharp_server`).
Roslyn keeps the name `roslyn_ls`, so nvim-lspconfig's root detection, fix-all code actions and inlay hints work
with both.

## Installing the stack (Arch / Omarchy)

```bash
sudo pacman -S --needed dotnet-sdk aspnet-runtime aspnet-targeting-pack
dotnet tool install --global roslyn-language-server --prerelease
dotnet tool install --global dotnet-ef
```

`~/.dotnet/tools` has to be on `PATH` for `dotnet ef` and for other shells to find Roslyn. The Neovim server
also looks there directly, so editing works before the shell is restarted. Mason installs `csharpier`,
`csharp-language-server` and `netcoredbg` on the next start (or `:MasonInstall csharpier csharp-language-server netcoredbg`).

`<leader>cSr` installs or updates Roslyn from the editor; `<leader>cSf` does the same for `dotnet-ef`. Both open
the command in the integrated terminal so its progress and any error are visible.

## `<leader>c` menu (only in `*.cs`)

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md). What they do, at the solution or project root:

- **dotnet**: run, watch with hot reload, build, publish Release, restore and SDK info. Commands run in the
  integrated terminal at the folder of the `.sln`/`.slnx`/`.csproj`; when a solution has several projects the
  action asks which one. `run`/`watch` use the launch profile the C# settings chose (`first`, `ask` or `none`).
  With no project around the current buffer (dashboard, tree, terminal) it falls back to the working directory;
  with no project at all the command is bare (`dotnet build` in the cwd) instead of a broken `--project ''`.
- **HTTP test file** (`h`): reads `Program.cs` next to the .csproj and writes `requests.http` (Rider/JetBrains
  format: one request per `MapGet/MapPost/…`, `{param}` → `world`, base URL from the first launch profile):
  created once, never overwritten, opened, and the GET routes fired with curl in a separate `http test`
  terminal (never the one the app runs in). Start the app first (`<leader>cr`).
  Routes behind `MapGroup("/prefix")` keep only their suffix.
- **Noodle collection** (`No`): generates `noodle/` next to the .csproj from the same routes — `settings.yml`
  (env `local`), `.environments/local.env` (base URL), one `.yml` request per route with native `:param`
  tokens + `path_params` samples and status-200 asserts on reads — and opens it in the Noodle TUI in its own
  `noodle` terminal. Files that exist are never overwritten. From the TUI: send requests, run the collection,
  or automate with `noodle collection run ./noodle --env local` (CI-ready). Needs the `noodle` binary on PATH.
- **Tests in the editor** (`m` nearest, `M` file, `A` all, `.` again, `T` toggle, `O` output): xUnit (`[Fact]`,
  `[Theory]`), NUnit (`[Test]`, `[TestCase]`) and MSTest (`[TestMethod]`, `[DataTestMethod]`). Marks per test,
  a failure as a diagnostic on the stack-trace line with the assertion's message, the quickfix list, a summary.
  `T` goes from `Foo.cs` to `FooTests.cs` (and back), opening a new path when the test file does not exist yet.
  Tests run with `dotnet test` and a TRX report (`--logger trx`); the report is parsed locally.
- **Packages**: `P` adds one, `N` searches NuGet (`dotnet package search --format json`, results by relevance
  with downloads), `U` lists outdated packages and upgrades the chosen one, `Q` puts vulnerable packages
  (severity and advisory) in the quickfix list, `R` removes one.
- **Solution / project** (`L`): list and open solutions/projects, add a project to the solution
  (`dotnet sln add`), add a project reference (`dotnet add reference`). `n` creates a new project from a
  `dotnet new` template.
- **Solution Explorer** (`Lo`): the Rider-like full-screen view (`csharp/explorer.lua` on
  `utils/csharpsolution.lua`): left, the solution by folder with TFM/output/test badges; right, the selected
  project (TFMs, SDK, output kind, dependencies resolved from `ProjectReference`, direct packages). Keys:
  `Enter` open the `.csproj`, `b` build it, `r` run it, `a` add it to the solution, `/` filter, `Tab` fold a
  folder. Edits happen through `dotnet sln`/`dotnet add` in the terminal (no drag-and-drop tree editing).
- **Run Configurations** (`Gr`): the saveable dropdown (`csharp/run.lua` on `utils/csharprun.lua`): launch
  profiles per project, Docker/Compose when present, and saved custom/compound configs
  (`stdpath("state")/csharp-run.json`, one entry per root). Keys: `Enter` run, `d` debug (dotnet, netcoredbg),
  `s` save as custom (name + command), `x` delete a saved one, `/` filter.
- **NuGet Manager** (`x`): the visual manager (`csharp/nuget.lua` on `utils/csharpnuget.lua`): Direct /
  Transitive / Vulnerable / Outdated groups from `dotnet list package --format json`, right pane with
  versions, project, advisory and the `obj/project.assets.json` graph (`depends on`). Keys: `Enter` update
  to latest, `a` add, `x` remove a direct package, `/` filter. Without `assets.json` (`dotnet restore`
  first) transitive packages are flat grouped by framework.
- **EF Core**: `dotnet ef migrations add <name>` and `dotnet ef database update` (needs the global `dotnet-ef`).
- **Format**: CSharpier through conform (`f`), `dotnet format` (`F`) and its verification mode (`v`).
- **Inlay hints** (`H`): Roslyn's parameter/type hints for this buffer; off by default, saved in the C# settings.
- **Debug** (`<leader>cD`): netcoredbg on the built assembly, breakpoints and the dap-view panel. The project is
  built first; the URL is taken from the first `Properties/launchSettings.json` profile when there is one, otherwise
  Kestrel's default. Use `dotnet watch` while editing instead of restarting the debugger.
- **Setup** (`<leader>cS`): `.editorconfig`, `Directory.Build.props` (nullable, implicit usings, analyzers,
  warnings as errors), `global.json` pinned to the installed SDK, GitHub Actions (restore, format check, build
  with `-warnaserror`, tests), a multi-stage ASP.NET Dockerfile and its `.dockerignore`, plus the shared
  Makefile (`.NET` preset) and `.gitignore` tools. Never overwrites. `Sr` installs/updates Roslyn, `Sf` `dotnet-ef`.

## Smart completion (`utils/csharpsmart.lua`)

A blink.cmp source for `cs` that reads the treesitter tree and a zero-token index of the project
(`utils/csharpindex.lua`). It appears next to Roslyn, not instead of it:

- **`ctor`**: a constructor built from the class's uninitialized private fields (their types and names).
- **`props`**: get-only properties for the private fields (`_service` → `public INoteService Service => _service;`).
- **`dbSet`** inside a `DbContext`: `public DbSet<Entity> Entities => Set<Entity>();` for every entity of the
  project (a type with an `Id`, not a service/controller/DbContext), with its `using`.
- **`services.Add…`** inside a method or a top-level `Program.cs`: `AddScoped`, `AddSingleton` and
  `AddTransient` for every interface/service pair (`AddScoped<INoteService, NoteService>()`), with the `using`.
  The project index skips `bin`, `obj`, `Migrations`, generated files and tests.
- **declarations**: typing `cla`/`rec`/`int`/`str` at the top offers a class/record/interface/struct named after
  the file.
- **`override` / `implement`**: method templates at the class level.
- The `using` a suggestion needs is inserted after the snippet, never as an awkward fully-qualified name. The
  C# settings panel turns each part on or off; `settings.csharp.smart.enabled = false` disables the source.

The index is cached by file modification time and directory listing; a new file shows up after a moment (or on
the next restart), and the unsaved buffer always replaces its file on disk.

## Settings (`<leader>Sp` → C#)

| Setting | What it does |
|---|---|
| Language server | `auto` (Roslyn if installed), `roslyn`, `csharp_ls`; takes effect on restart |
| Smart completion | master switch for `csharpsmart` |
| Declaration / constructor / properties / DbSet / DI / usings | each group of suggestions |
| Inlay hints | Roslyn's parameter/type hints in C# buffers |
| Run profile | `first` of `launchSettings.json`, `ask`, or `none` for `dotnet run`/`watch` |

## Snippets

`namespace`, `class`, `record`, `interface`, `enum`, `prop`, `propg`, `field`, `ctor`, `method`, `async`, `if`,
`foreach`, `trycatch`, `using`, `switch`, `main`, `webapi` (minimal API with Swagger), `mapget`, `mappost`,
`controller`, `action`, `dbcontext`, `entity`, `options`, `xunit`, `monobehaviour` (Unity), `serializedfield`.

They are plain VSCode snippets (`nvim/snippets/cs.json`), so they work with blink.cmp's `snippets` source; the
built-in LSP completion remains the first source.

Razor (`nvim/snippets/razor.json`, prefix `page code inject using namespace implements attribute rendermode
functions parameter eventcallback if foreach for component ref`) and XAML (`nvim/snippets/xaml.json`, prefix
`window grid stackpanel button textbox textblock image resource style`) ship their own snippets. Unity
scripts are `cs`, so `monobehaviour`/`serializedfield` there plus `nvim/snippets/unity.json` for the
YAML files.

## Razor / Blazor

`.razor` and `.cshtml` are filetype `razor` (Neovim core). Treesitter `razor` highlights the markup; the
`html` LSP also attaches to `razor` (`nvim/lua/servers/html.lua`) for tag/attribute completion, and the
`<leader>c` menu (the same dotnet actions as C#: `r` run, `w` watch with hot reload, `b` build, `F` format)
is the hot-reload loop — there is no visual preview in Neovim, only the running app in its browser.
Full C# inside `@code` (go-to-definition, diagnostics, rename) needs `seblyng/roslyn.nvim`: it co-hosts
with Roslyn and supersedes the archived `rzls.nvim` (the stock `nvim-lspconfig` `roslyn_ls` warns that
Razor is not supported). Hot reload itself is already done (`dotnet watch`, `<leader>cw`). For
`tracking-system-amphenol` (ASP.NET API + Docker, no `.razor` today) nothing changes until a Blazor/MVC UI
is added; then `dotnet watch run` + the browser is the preview.

## XAML

`.xaml` is filetype `xaml` (`ftdetect/xaml.lua`), parsed as `xml`, formatted with `prettier` (the project's
`prettier-plugin-xml`). The `<leader>x` menu (`f` format, `b` build, `F` `dotnet format`, `u` restore,
`I` SDK info) runs at the `.sln`/`.csproj` root. Rider's XAML preview/designer has no Neovim equivalent:
`dotnet build` plus running the app is the check.

## Unity

Scripts are `cs` under `Assets/` (Roslyn + the C# menu). Scenes/prefabs/meta (`.unity`, `.prefab`, `.meta`,
`.anim`, `.controller`, `.mat`, `.asset`) are filetype `unity` (`ftdetect/unity.lua`), parsed as `yaml`,
formatted with `prettier`. The index skips `Library/`, `Temp/`, `Logs/`, `UserSettings/`, `Build/` and
`Builds/`, and `utils/csharpproj` recognises a Unity root (`Assets/` + `ProjectSettings/`). The `<leader>U`
menu (`o` open in Unity, `R` refresh Asset Database, `S` generate `.sln`, `I` project info, `f` format) is
for the YAML files and the project; Rider's scene preview remains inside the Unity Editor.

## Pitfalls

- **Razor LSP**: Treesitter + `html` give highlighting and markup completion today. Full C# in `.razor`
  needs `seblyng/roslyn.nvim` (co-hosting; `rzls.nvim` is archived). Until then, `@code` blocks are plain
  text for the LSP (compilation still via `dotnet build`). See the Razor section above.
- **XAML / Unity previews**: Rider draws XAML and scenes inside the IDE; Neovim shows `xml`/`yaml` syntax
  only. Use `dotnet build`/Unity itself for the visual check.
- **Roslyn is a prerelease tool**: `dotnet tool install --global roslyn-language-server --prerelease` is what
  Microsoft documents. If a version stops starting, switch the C# server to `csharp_ls` in the settings panel;
  it is stable and Mason-managed.
- **`dotnet` without SDK**: `dotnet --version` says "No .NET SDKs were found" when only `dotnet-runtime` is
  installed. ASP.NET projects also need `aspnet-runtime` to run and `aspnet-targeting-pack` to build.
- **Global tools and `PATH`**: a new shell needs `export PATH="$PATH:$HOME/.dotnet/tools"` (in `~/.bashrc`).
  Until then, use the absolute path or the `<leader>cS` actions, which run from the editor's environment.
- **Tests build first**: `dotnet test` restores/builds before running. The first run of a solution is slow; the
  following ones reuse the build. If the build fails there is no TRX, so the editor shows the runner's output
  (`O`) instead of marks.
- **Theories** have one result per case in TRX; the adapter collapses them into their method and keeps a failure
  over a pass. A test filter uses the fully qualified name (`FullyQualifiedName~Namespace.Class.Method`).
- **Test project discovery**: the solution root wins (so `dotnet test` sees every test project); without a
  solution it runs the test project, or the only project. `Foo.cs` ↔ `FooTests.cs` is what `T` looks for.
- **Debugging tests**: C# has no debug-test-under-cursor yet (the `Dt` key is not offered). Run the test with
  `m`, use its output, or launch the app with `Dd`.
- **Debugging ASP.NET**: netcoredbg launches the DLL, not `dotnet run`, so `launchSettings.json` is read only
  for `applicationUrl`; environment-specific secrets and profiles are not applied.
- **First Roslyn start** builds the project's MSBuild graph; a big solution takes a while. `:LspInfo` shows the
  server, `:LspRestart` restarts it after installing or updating it.
- **Inlay hints** ask Roslyn for semantic hints; they are off by default because they are visual noise, and can
  make a big file redraw more. Turn them on only where they help.
