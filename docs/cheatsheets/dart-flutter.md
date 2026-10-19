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

Four keys start an app (`lua/dartrun`):

| Key | Does |
|---|---|
| `<leader>dr` | run on the device and entry point you used last, at once |
| `<leader>dd` | the same, with the debug panel open from the start |
| `<leader>ds` | the same in **profile** mode (performance: no debugger, `<leader>dt` opens DevTools) |
| `<leader>dD` | asks the device, the entry point (`lib/main_dev.dart`…) and the mode (debug / profile / release) |

The device, the entry point and the last choice are remembered per project (`stdpath("state")/dartrun.json`), so after
the first run `r`, `d` and `s` ask nothing; with a device missing they ask only for it (a single connected device is
taken without asking). Devices come from `flutter devices --machine` (~0.5 s) and are sorted last used, phones,
emulators, desktop, web; the ones the project has no folder for (`web/`, `ios/`…) are not offered. `<leader>ds` and
`<leader>dD` while an app runs stop it and start the new one (`r`/`d` never interrupt it). The iOS simulator only
runs debug (Flutter's own rule; Android emulators do run profile). Project configurations you declare yourself
(`require("flutter-tools").setup_project`, with flavors or dart-define) win for `r` and `d`; a plain Dart package (no
Flutter) is run by flutter-tools as before. With FVM, the project's SDK (`.fvm/flutter_sdk`) is used when it is installed.

**Statusline.** A chip follows the app: `◌ Pixel 7` while it builds, `▶ Pixel 7` running, `▶ Pixel 7 · profile` (blue:
it is not the build you debug), `⏸ Pixel 7` stopped at a breakpoint (yellow). It disappears when the session ends.

**Quiet by default.** A run puts nothing on the screen: the app's log goes to a hidden buffer (`<leader>dl` opens or
closes it; `settings.flutter.log = "split"` opens it in a bottom split at every run, as before), the debug panel
(nvim-dap-view) opens with `<leader>dd` or when the app stops at a breakpoint, and its errors still arrive as notes.
`<leader>dH` hides whatever is open (log, debug panel, widget outline); with nothing open it shows the log.

**Profile in practice.** `<leader>ds` on a phone (or `Linux`/`Chrome`): hot reload keeps working, breakpoints do not.
Open DevTools with `<leader>dt` for the Performance and CPU tabs. Profile on a simulator or an emulator measures
the host's speed, not the device's: use a real device for numbers.

It runs through nvim-dap, so a breakpoint (`<leader>db`, `<leader>dB` with a condition) stops it in
any run; `<leader>dd` does the same explicitly and opens the panel at once. Saving a `.dart` file hot-reloads the running app and saving
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

## Tests inside the editor

| Key | Runs |
|---|---|
| `<leader>dm` | the test or group under the cursor (the whole file when the cursor is outside any) |
| `<leader>dM` | the file |
| `<leader>dA` | every test of the package |
| `<leader>d.` | the last run again |
| `<leader>dT` | jumps between `lib/x.dart` and `test/x_test.dart`, creating the test file (not saved) with its imports and a `group` |
| `<leader>dw` | the raw output of the last run (a compile error that stopped it before any test, toolchain warnings) |

`flutter test` or `dart test` (whichever the package is) with the JSON reporter (`lua/darttest`). Each test line gets a
mark as it finishes (`✓` with its time, `✗`, `○` skipped, `…` running) and the statusline counts `test ✓12 ✗1 …`. A
failure becomes a diagnostic on the line its stack trace points at (the `expect` that failed) with the expected/actual
text and whatever the test printed; the failures go to the quickfix list and one note sums the run up
(`Tests failed: 2 of 3 · 1 skipped · calc add fails`). Results are kept per file, so a test file opened later shows them.
A test is found by its literal name, groups included (`--plain-name "calc add sums"`): a name with interpolation
(`'renders $x'`) cannot be targeted, run its group or the file. Flutter compiles before the first test: a single
widget test takes ~45 s the first time on a big app, and much less afterwards.

## Dependencies

`<leader>dU` writes, next to each dependency of `pubspec.yaml` that is behind, what it can move to: `↑ 2.5.6` (green:
`pub upgrade` takes it, the constraint allows it), `latest 3.0.0 (change the constraint)` (yellow) or
`discontinued` / `security advisory` (red); saving `pubspec.yaml` clears them. `<leader>dP` adds packages (`name`,
`dev:name`, `name:^1.2.0`, several at once) with `pub add`; its error, if any, is one note. Both ask pub.dev (network).
`<leader>dp` is `pub get` (saving `pubspec.yaml` also runs it).

## Translations

Saving an `.arb` file in a package with `l10n.yaml` runs `flutter gen-l10n` in the background, so
`AppLocalizations.of(context).newKey` exists for the LSP at once; a mistake (an ICU syntax error, a missing placeholder)
comes back as one note with gen-l10n's own message.

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
