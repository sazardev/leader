# Dart / Flutter

Filetype: `dart`.

## Herramientas

| Qué | Con |
|---|---|
| LSP | `dartls`, gestionado por **flutter-tools.nvim** (no por `vim.lsp.enable`) |
| Formato (al guardar y `<leader>fm`) | `dart_format` |
| Treesitter | `dart` |
| Snippets | los de Flutter de friendly-snippets (el language id `flutter` se pide explícito para filetype `dart`) |

## Menú `<leader>d` (solo en `*.dart`)

Las teclas están en [`CHEATSHEET.md`](../../CHEATSHEET.md) (generado; no se duplican aquí).

Necesita `pubspec.yaml`: detecta si es Flutter (bloque `flutter:`) o Dart puro y usa el comando correcto (`flutter test` / `dart test`, etc.).
