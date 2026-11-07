# C# / .NET

Filetype: `cs`. Pack `csharp`.

## Tools

| What | With |
|---|---|
| LSP | **Roslyn** (Microsoft's official server, a global `dotnet tool`) when it is installed; **csharp-ls** (Mason) as the fallback |
| Format on save | `csharpier` (Mason, or the project's local tool) |
| Debug | `netcoredbg` (Mason): the assembly `dotnet build` produced |
| Tests | `dotnet test` with a TRX report, inside the editor (`langtest`, adapter `dotnet`) |
| Treesitter | `c_sharp` |
| SDK | `dotnet-sdk` (the runtime alone is not enough) |

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
`controller`, `action`, `dbcontext`, `entity`, `options`, `xunit`.

They are plain VSCode snippets (`nvim/snippets/cs.json`), so they work with blink.cmp's `snippets` source; the
built-in LSP completion remains the first source.

## Pitfalls

- **Razor / `.cshtml` / `.razor`**: nvim-lspconfig's `roslyn_ls` only attaches to `cs` and explicitly warns that
  Razor needs `seblyng/roslyn.nvim`; this config does not add that plugin. C# classes, minimal APIs and controllers
  are fully covered.
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
