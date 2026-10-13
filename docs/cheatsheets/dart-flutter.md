# Dart / Flutter

Filetype: `dart`.

## Tools

| What | With |
|---|---|
| LSP | `dartls`, managed by **flutter-tools.nvim** (not by `vim.lsp.enable`) |
| Format (on save and `<leader>fm`) | `dart_format` |
| Treesitter | `dart` |
| Snippets | the Flutter ones from friendly-snippets (the `flutter` language id is requested explicitly for filetype `dart`) |

## `<leader>d` menu (only in `*.dart`)

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md) (generated; not duplicated here).

Requires `pubspec.yaml`: it detects whether the project is Flutter (`flutter:` block) or plain Dart and uses the right command (`flutter test` / `dart test`, etc.).
