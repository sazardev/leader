<!-- name: Brutal terminal -->
<!-- desc: raw, high-contrast TUI: heavy block borders, all-caps labels, reverse-video blocks, 2-3 colors at most -->

# DESIGN.md: Brutal terminal

A raw terminal design: heavy block characters, ALL-CAPS labels, reverse-video slabs and two or three colors used at full
strength. No rounded corners, no gradients, no decoration that is not structure. Loud, honest and very fast to read.

## Principles

- **Structure is the decoration**: blocks, rules and caps do all the work.
- **Maximum contrast**: text is either full foreground or reverse video; nothing in between except one muted tone.
- **Few colors, used hard**: the default foreground, one accent, and red for danger.
- **No softness**: square corners, no animation for its own sake, no rounded anything.
- **Big targets**: wide bars and generous blocks make state visible from across the room.

## Color

| Token | ANSI 16 | 256 | Truecolor | Use |
| --- | --- | --- | --- | --- |
| `fg` | default fg (bold) | default | default | Text |
| `bg` | default bg | default | default | Never painted |
| `slab` | reverse video (SGR 7) | — | — | Titles, selection, status bar |
| `accent` | 3 (yellow) | 226 | `#FFFF00` | Focus, the one thing that matters now |
| `danger` | 1 (red) | 196 | `#FF0000` | Errors, destructive actions |
| `muted` | 8 | 242 | `#6C6C6C` | Disabled only |

- At most 3 colors on any screen (`fg`, `accent`, `danger`). Success is stated in words (`DONE`), not a fourth color.

## Typography

| Role | Style | Use |
| --- | --- | --- |
| Title | bold, ALL CAPS, reverse video slab | Panel and screen titles |
| Label | ALL CAPS, bold | Field names, column headers |
| Body | default weight, sentence case | Values, messages |
| Key | `[ENTER]` `[Q]` bold | Shortcuts |
| Number | bold, right-aligned | Counts, metrics |

- No italics, no dim text except disabled items. Big numbers may use a 3-row block font built from `█▀▄`.

## Spacing and layout

- Unit = one cell. Panels separated by a full block column or a 1-cell gap; padding 1 cell inside slabs.
- Minimum 80×24; below it a full-screen `TERMINAL TOO SMALL: NEED 80x24` slab.
- Layout: one dominant pane; secondary panes stacked to the right from 120 columns.
- Status bar: full-width reverse video slab on the last row.

## Shape and elevation

| Token | Glyphs | Use |
| --- | --- | --- |
| border-heavy | `█` full block frame, or `▛▀▜▌▐▙▄▟` | Panels |
| rule | `━` or `▀` row | Section dividers |
| slab | reverse video row | Titles, selection, buttons |
| corner | square only | Always |

- Elevation: a dialog is a slab-titled heavy frame drawn over cleared cells, with a 1-cell `█` shadow offset right and down.

## Motion

| Token | Value | Use |
| --- | --- | --- |
| frame-budget | 10 fps | Spinners only |
| spinner | `█▓▒░▒▓` (6 frames, 100 ms) | Activity |
| blink | none | Never blink |
| transition | none | Screens switch instantly |

- Reduced motion: spinner becomes `WORKING…` static text.

## Components

- **Title slab**: full-width reverse video, ALL CAPS, left-aligned name and right-aligned context.
- **Lists/tables**: header row ALL CAPS bold, selected row reverse video, no zebra stripes.
- **Panes**: heavy frame; the focused one in `accent`.
- **Buttons**: `[ SAVE ]` reverse video when focused; destructive in `danger`.
- **Progress**: `███████░░░░░ 58%` full blocks for done.
- **Prompts**: `> ` in `accent`, input on the same row.
- **Help bar**: `[Q] QUIT  [/] SEARCH  [ENTER] OPEN`.
- **Empty/loading/error**: one slab line: `NOTHING HERE. [N] NEW`, spinner + `LOADING`, `ERROR: <cause>. [R] RETRY` in `danger`.

## Accessibility

- High contrast by design; reverse video works in every theme and with `NO_COLOR` (hierarchy keeps working without color).
- ALL CAPS only on short labels (≤ 3 words); messages stay in sentence case for screen readers and reading speed.
- Plain mode: frames removed, slabs become `== TITLE ==` lines.
- Keyboard only; focus always shown by reverse video.

## Rules for agents

- Use only the three color roles; adding a color needs a reason in the PR.
- Never use rounded borders, gradients or italics.
- Bubble Tea/Lip Gloss: `lipgloss.BlockBorder()` for frames, `Reverse(true)` for slabs, styles in one `styles.go`. Ratatui: `BorderType::Thick` or custom `symbols::border::FULL`, `Modifier::REVERSED` for slabs.
- Every destructive action asks with a `danger` slab dialog.
- Test with `NO_COLOR=1` and at 80×24.
