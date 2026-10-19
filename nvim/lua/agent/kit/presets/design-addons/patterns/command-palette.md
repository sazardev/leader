<!-- name: Command palette -->
<!-- desc: keyboard-first search-everything palette, actions and shortcut display -->
<!-- for: all -->

## Components

- GUI: open with Cmd/Ctrl+K (and "/" when no input is focused); centered overlay 600 px wide, 15% from the top, search input 48 px with the placeholder "Search or run a command...", results list max 8 rows visible, 40 px each, scrollable.
- GUI: one list mixes navigation, objects and actions in labelled groups (Recent, Pages, Records, Actions); with an empty query show Recent and common actions; ranking favors prefix matches, then recency, then frequency; fuzzy matching tolerates typos.
- GUI: each row: icon, label with the matched characters emphasized, secondary text (location or type) muted, and the shortcut right-aligned as keycaps (`Ctrl` `Shift` `P`); show the platform's symbols (Cmd on macOS, Ctrl elsewhere).
- GUI: Up/Down move the highlight, Enter runs, Cmd/Ctrl+Enter opens in a new tab or alternate target, Esc closes, Backspace on an empty query leaves a scoped mode; scoped prefixes (`>` actions, `@` people, `#` pages) are listed in the footer hints.
- GUI: actions that need input continue inside the palette as a second step with a breadcrumb chip ("Move to..."), never a new dialog; destructive actions ask for confirmation before running.
- GUI: no results shows "No matches for 'x'" with the nearest alternative or "Search all records" as the action; slow sources show a spinner row while local results are already visible.
- GUI: show results in under 100 ms for local items; remote results append without moving the highlighted row.
- TUI: `:` or Ctrl+P opens a prompt at the bottom with a list above it, same ranking, `Tab` completes, Enter runs, Esc cancels; the key binding appears at the right of each row.

## Accessibility

- Implement as a combobox with `aria-activedescendant`, announce the results count, keep focus in the input, and make every command also reachable without the palette.

## Rules for agents

- Every action in the palette shows its shortcut when it has one; every shortcut appears in the palette.
- Never make the palette the only way to reach a feature.
