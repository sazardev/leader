# Dart / Flutter

Filetype: `dart`. The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md) (generated; not duplicated here).

## Tools

| What | With |
|---|---|
| LSP | `dartls`, managed by **flutter-tools.nvim** (not by `vim.lsp.enable`); not started in light mode |
| Format (on save and `<leader>fm`) | `dart_format` |
| Treesitter | `dart` |
| Debugger | **nvim-dap** + **nvim-dap-view** (`plugins/tools/dap.lua`), loaded only when you debug |
| Code generation | `dart run build_runner` from `lua/dartgen` (watch in the background, state in the statusline) |
| Completion | `utils/dartsmart.lua` (declarations for the project's stack) + the LSP + the Flutter snippets of friendly-snippets |

## Run, hot reload, debug

`<leader>dr` runs the app through nvim-dap, so a breakpoint (`<leader>db`, `<leader>dB` with a condition) stops it in
any run; `<leader>dd` does the same explicitly. Saving a `.dart` file hot-reloads the running app and saving
`pubspec.yaml` runs `pub get` (flutter-tools). While stopped: `<leader>dc` continue, `<leader>dn` step over, `<leader>di`
into, `<leader>dO` out; the panel (watches, scopes, breakpoints, threads, REPL) opens and closes with the session
(`<leader>du` toggles it). The launch configuration is flutter-tools' own ("Launch flutter" on `lib/main.dart`, or the
target of its project config): never empty `dap.configurations.dart`, or nothing launches.

## Code generation (build_runner)

For packages with `build_runner` in `pubspec.yaml` (freezed, json_serializable, riverpod_generator, drift…):

- `<leader>dg` starts / stops `build_runner watch` for the file's package, in the background. The statusline shows
  `gen …` while it builds, `gen` when it is up to date and `gen ✗ N` when it failed.
- A failed build puts its errors as diagnostics on the file and line they point at (source = the builder, e.g.
  `json_serializable`) plus one note; the next good build clears them and says `Codegen fixed`.
- `<leader>dL` shows the whole output; `<leader>dG` builds once.
- Opening a file whose generated part (`part 'x.g.dart';`, `part 'x.freezed.dart';`) does not exist says so once.
- Light mode: `<leader>dg` builds once instead of keeping a watch (a Dart VM stays resident).

Both output formats are understood (build_runner ≥ 2.5: `Built with build_runner…` / `E builder on file:`; older:
`[INFO] Succeeded after…` / `[SEVERE]`). build_runner 2.16 removed `--delete-conflicting-outputs`: it is not passed.

## Completion for the stack

At the start of a top-level declaration (column 0) the completion offers what `pubspec.yaml` says the package uses,
named after the file (`snippet_filter_bar.dart` → `SnippetFilterBar`, `cart_provider.dart` → `cart`):

| Item | Needs | Gives |
|---|---|---|
| `consumer`, `consumerstateful` | flutter_riverpod / hooks_riverpod | ConsumerWidget, ConsumerStatefulWidget + its State |
| `riverpod`, `riverpodnotifier` | riverpod_annotation | `@riverpod` function provider, `@riverpod` Notifier class |
| `freezed`, `freezedunion` | freezed | `@freezed abstract class` (with `fromJson` when json_serializable is there), `sealed` union |
| `stateless`, `stateful` | flutter | StatelessWidget, StatefulWidget + its State |

Accepting one also adds the import and `part` lines it needs and the file lacks (`utils/dartheader.lua`), so
`part 'x.g.dart';` is never forgotten. They are applied after the snippet (the source's `execute`), not as
`additionalTextEdits`: blink applies those after expanding the snippet, and in a new file an insert at the typed line
lands below the class.

## The agent with Dart

- `<leader>at` (convert) follows the stack: JSON → freezed classes (or `@JsonSerializable()` without freezed), a SQL
  table → a drift `Table`. The import and `part` lines are added when you accept, and a snake_case key the model left
  without `@JsonKey(name: …)` gets it by rule (it would deserialize as null). Skipped when `build.yaml` has
  `field_rename`.
- After accepting a change, saving runs `dart analyze` on that file (machine format) and blames only the errors
  inside what was accepted.
- "Fix from output" (`<leader>aAo` / `aAO`) reads `flutter analyze` and `dart analyze` output.
- Generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.mocks.dart`, protobuf) are never edited by the agent
  (explain/ask still work there) and are left out of its context and of code search (`utils/generated.lua`).

## Pitfalls

- Requires `pubspec.yaml`: it detects whether the project is Flutter (`flutter:` block) or plain Dart and uses the
  right command (`flutter test` / `dart test`, etc.).
- The Dart debug adapter pauses "on entry" and resumes by itself: calling `continue` there gets nvim-dap's "not
  focused on any stopped thread" question.
- Neovim's snippet parser rejects nested placeholders (`${1:Future<${2:T}>}`): keep one placeholder per type.
