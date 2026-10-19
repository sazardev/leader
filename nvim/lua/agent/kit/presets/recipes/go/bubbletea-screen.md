<!-- name: Bubble Tea screen -->
<!-- desc: a TUI screen (model, update, view), its keys, its styles and a teatest golden test -->
<!-- for: go+tui -->
<!-- input: name | Name of the screen (e.g. Settings, History) -->
<!-- input: shows | What it shows and what the keys do (one sentence) -->

# Recipe: the {{name_pascal}} screen (TUI)

{{shows}}

## Make

- `{{name_camel}}Model` with `Init`, `Update`, `View` in the UI package STACK.md names (one screen per file, as the existing ones), opened from the screen that leads to it.
- Its key map (`key.Binding`s with help text) and a help line drawn from it (bubbles `help`).
- Its styles from the project's styles file (Lip Gloss), DESIGN.md's tokens; centered and framed as DESIGN.md's `## Screens` draws it when it does.
- Messages for what it loads (a `tea.Cmd` per IO, never IO inside `Update`).

## Rules

- `View` is pure: it only reads the model; widths come from `tea.WindowSizeMsg`, and a terminal too small says so instead of breaking the layout.
- Every key the help line shows works; `esc`/`q` go back as on the other screens.

## Tests

- `Update` unit tests: each key changes the model as the sentence above says.
- A teatest golden test of the first frame at DESIGN.md's minimum size (the golden file is written by the test, never by hand).
