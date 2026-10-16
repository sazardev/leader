<!-- name: Braille -->
<!-- desc: dense TUI where Braille cells (U+2800–28FF) are a 2x4 pixel grid: sparklines, charts, art, spinners -->

# DESIGN.md: Braille

A terminal design built on the Braille block (U+2800–U+28FF): every cell is a 2×4 grid of dots, so one character row holds
four pixel rows. Data becomes shape (sparklines, area charts, heatmaps, maps, small art) inside a quiet, almost invisible
chrome. Works in any UTF-8 terminal with a font that has the Braille block (all common monospace fonts and Nerd Fonts do).

## Principles

- **Data is the interface**: charts and sparklines carry the meaning; borders, labels and color stay quiet around them.
- **Resolution through glyphs**: use the 2×4 dot grid before reaching for more rows; a 40-cell sparkline shows 80 samples.
- **Quiet chrome**: one thin border style at most, dim labels, no decorative color.
- **Density with rhythm**: dense panels separated by one blank cell column/row, never by heavy frames.
- **Degrade cleanly**: without UTF-8 the same views render with ASCII ramps (` .:-=+*#`), never as tofu.

## Color

Colors are terminal roles first (ANSI 16), truecolor only for data ramps. Hex values are the truecolor defaults on a dark terminal.

| Token | ANSI 16 | 256 | Truecolor (dark) | Use |
| --- | --- | --- | --- | --- |
| `fg` | default fg | default | terminal default | Text, values |
| `bg` | default bg | default | terminal default | Never painted over the whole screen |
| `muted` | 8 (bright black) | 244 | `#7C7F87` | Labels, axes, borders |
| `accent` | 6 (cyan) | 45 | `#5FD7FF` | Current series, focus |
| `series-2` | 5 (magenta) | 176 | `#D787D7` | Second series |
| `series-3` | 3 (yellow) | 179 | `#D7AF5F` | Third series |
| `success` | 2 (green) | 114 | `#87D787` | Up, healthy |
| `warning` | 3 (yellow) | 221 | `#FFD75F` | Thresholds |
| `danger` | 1 (red) | 203 | `#FF5F5F` | Down, errors |
| `selection` | reverse video (SGR 7) | — | — | Selected row |

- Data ramps (heatmaps, density): 5 steps from `muted` to `accent` in truecolor (interpolated in OKLCH), 256-color nearest, ANSI 16 falls back to dot density alone.
- A chart never relies on color: series differ by position, label or dot density too.

## Typography

| Role | Glyphs / style | Use |
| --- | --- | --- |
| Value | default weight | Numbers, cell contents |
| Label | dim (SGR 2) | Axis labels, field names |
| Heading | bold, no color | Panel titles |
| Key hint | bold `accent` | Shortcuts in the help bar |
| Plot | U+2800–U+28FF | Sparklines, line/area charts, braille art |
| Spinner | `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` | Activity |
| Bars | `▁▂▃▄▅▆▇█` (eighth blocks) | Vertical bars when Braille is too fine |

- Numbers right-aligned in fixed-width columns; units dim after the value (`42 ms`).
- Braille dot numbering: dots 1-2-3-7 left column, 4-5-6-8 right; code point = U+2800 + bit mask (dot n → bit n-1).

## Spacing and layout

- Unit = one cell. Gutters: 1 column between panels, 1 row between sections; inner padding 1 cell horizontally, 0 vertically.
- Minimum size 80×24; below it show a single centered message with the required size. Design breakpoints at 80, 120 and 160 columns: 1, 2 and 3 panel columns.
- Plots resize with the panel: recompute samples per cell on every resize (`2 × width` samples per row).
- Status bar on the last row, help bar on it or above it; content never under them.

## Shape and elevation

| Token | Glyphs | Use |
| --- | --- | --- |
| border-none | — | Default: panels separated by space |
| border-thin | `┌─┐│└┘` | Only when panels touch |
| border-focus | thin border in `accent` | Focused pane |
| divider | `─` in `muted` | Between sections |

- Elevation = layering: dialogs draw over content with a cleared rectangle and a thin border; no shadows.
- Selected rows use reverse video, never a painted background color.

## Motion

| Token | Value | Use |
| --- | --- | --- |
| frame-budget | 15 fps (66 ms) | Live charts, spinners |
| spinner | 10 frames, 80 ms each | Indeterminate work |
| chart-scroll | 1 sample per tick, tick = data rate | Streaming sparklines |
| reveal | none | Content appears at once |

- Redraw only changed regions; never redraw faster than data arrives.
- Reduced motion (`REDUCED_MOTION=1` or a setting): spinners become a static `…`, charts update without scrolling animation.

## Components

- **Sparkline**: one row of Braille, latest sample at the right, min/max as dim labels at the ends.
- **Line/area chart**: Braille canvas, axes in `muted`, at most 3 series, legend in the panel title.
- **Heatmap**: Braille dot density or the color ramp, with a scale under it.
- **Lists/tables**: no grid lines; header dim; selected row reverse video; columns aligned by cell.
- **Panes**: titled with the panel name in bold; focus shown by the `accent` border or title.
- **Status bar**: mode, context, counters; **help bar**: `key action` pairs, keys in `accent`.
- **Spinner/progress**: Braille spinner + label; determinate progress as a row of eighth blocks with a percentage.
- **Empty/loading/error**: one centered line (`No data yet`, spinner + `Loading`, `danger` message + retry key).

## Accessibility

- `NO_COLOR` or `TERM=dumb`: no colors; hierarchy by bold/dim; charts keep working (they are shape).
- Plain mode (`--plain`, non-TTY or screen reader setting): charts become text summaries (min, max, last, trend) and tables become `key: value` lines.
- Every view works with the keyboard alone; focus is always visible without color (border or reverse video).
- Contrast: never use `muted` for values, only for labels; data in `fg` or series colors with ≥ 4.5:1 on common dark/light themes (approx.).

## Rules for agents

- Render Braille through one canvas helper (set dot, plot line, clear); never hand-assemble code points in views.
- Bubble Tea: keep the canvas in the model, build it in `View()` from the data; style with Lip Gloss roles from one `styles.go`. Ratatui: use `Canvas` with `Marker::Braille` and `Sparkline`/`Chart` widgets.
- Always provide the ASCII fallback (`LANG` without UTF-8) and the plain-text summary of every chart.
- Never paint the screen background; never more than 3 series in one chart.
- Resize recomputes the layout and the sample count; test at 80×24, 120×40 and 200×60.
