<!-- name: Monitoring dashboard -->
<!-- desc: dense htop-style TUI: meters, sparklines, threshold colors, sortable process table, function-key bar -->

# DESIGN.md: Monitoring dashboard

A dense terminal dashboard in the htop / btop tradition: meters and sparklines on top, a sortable table below, a
function-key bar at the bottom. Built for scanning live numbers at a glance on any terminal, including over SSH.

## Principles

- **Glanceable**: the state of the system reads in one second from meters and threshold colors.
- **Dense but aligned**: every number in a fixed-width column, right-aligned.
- **Color is a threshold**: green ok, yellow warning, red critical; never decoration.
- **Live but calm**: values update in place; nothing flickers or reflows.
- **Keys are visible**: the function-key bar always shows what each key does.

## Color

| Token | ANSI 16 | 256 | Truecolor (dark) | Use |
| --- | --- | --- | --- | --- |
| `fg` | default fg | default | terminal default | Values |
| `bg` | default bg | default | terminal default | Never painted globally |
| `muted` | 8 | 244 | `#7C7F87` | Labels, units, axes |
| `ok` | 2 (green) | 114 | `#87D787` | Below warning threshold |
| `warn` | 3 (yellow) | 221 | `#FFD75F` | Warning threshold (default 70%) |
| `crit` | 1 (red) | 203 | `#FF5F5F` | Critical threshold (default 90%) |
| `accent` | 6 (cyan) | 45 | `#5FD7FF` | Headers, sort column, focus |
| `bar-key` | reverse 6 | — | — | Function-key labels (F1…F10) |
| `selection` | reverse video | — | — | Selected row |

- Meter fills shade from `ok` to `warn` to `crit` by value; in ANSI 16 a meter is one color by its current threshold.
- `NO_COLOR` / dumb terminal: thresholds shown as markers (`!` warn, `!!` crit) after the value.

## Typography

Monospace cells; weight and glyphs carry hierarchy.

| Role | Glyphs / style | Use |
| --- | --- | --- |
| header | bold, `accent` | Column headers, panel titles |
| value | default | Numbers (always right-aligned, fixed width) |
| label | `muted` | Meter labels (`CPU`, `MEM`, `SWP`) |
| meter | `[|||||||     45.2%]` (ASCII) or `▕████▌    ▏` (Unicode, 1/8 blocks) | Usage bars |
| sparkline | `▁▂▃▄▅▆▇█` (Unicode) or braille `⣀⣤⣶⣿`; ASCII fallback `_.-=^` | History (last 60 samples) |
| unit | `muted`, no space before (`45%`, `1.2G`) | Units |

Human units with 3 significant digits: `987K`, `1.23G`; times as `1d02h`, `03:14`.

## Spacing and layout

- Minimum 80×24; layout grows to fill, never shrinks below that (show "terminal too small" instead).
- Top: meters in 2 columns (CPU cores split across them), 1 row each; sparklines to the right when width ≥ 120.
- Middle: the table fills the remaining height; columns PID 7, USER 9, CPU% 6, MEM% 6, TIME 9, COMMAND rest.
- Bottom: 1-row function-key bar.
- 1 cell padding inside panels; panels separated by a single box-drawing line.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| `border` | single `┌─┐│└┘` (Unicode) / `+-|` (ASCII) | Panels |
| `focus-border` | heavy `┏━┓┃┗┛` in `accent` | Focused panel |
| `overlay` | double `╔═╗║╚╝` | Dialogs (kill, filter) drawn over the table |
| `selection` | reverse video full row | Selected process |

## Motion

| Token | Value |
| --- | --- |
| `refresh` | 1000ms default (configurable 250ms–10s) |
| `spinner` | braille `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` at 80ms, only while loading |
| `fps-max` | 30 |

- Redraw only changed cells (diffed frame buffer); sorting never moves the selected row out of view.
- Reduced motion / slow link: refresh 2000ms, no spinner animation (static `…`).

## Components

- **Meter**: label, bar, value; threshold color; optional per-core breakdown.
- **Sparkline panel**: series name, current value, min/max in `muted`.
- **Process table**: sortable by any column (`accent` header + `▲▼`), tree view toggle, incremental filter (`/`), search (`F3`).
- **Function-key bar**: `F1Help F2Setup F3Search F4Filter F5Tree F6Sort F9Kill F10Quit` (key in `bar-key`, label default).
- **Dialogs**: kill (signal list), sort column chooser, filter input; Esc cancels.
- **States**: loading (spinner + "collecting…"), no permission (row shows `—` with reason in footer), error (footer message, keeps last good data).

## Accessibility

- Thresholds readable without color (markers in `NO_COLOR`, and values always shown as numbers).
- Every function also has a letter shortcut (`q` quit, `k` kill, `s` sort) besides F-keys (some terminals eat F-keys).
- Plain mode (`--plain` / not a TTY): prints one snapshot as text table, no box drawing.
- Contrast: thresholds use bright variants on dark terminals if the normal ones are below 4.5:1.

## Rules for agents

- Fixed-width, right-aligned numeric columns; units in `muted` without a space.
- Colors only from threshold/role tokens via one theme module (Lip Gloss styles / Ratatui `Style`), never inline escapes.
- Redraw by diff at most `fps-max`; never clear the whole screen on refresh.
- Always render the function-key bar and keep it in sync with the active keymap.
- Fall back to ASCII meters and sparklines when the terminal or font lacks Unicode blocks.
