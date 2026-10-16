<!-- name: Modern TUI (Charm-style) -->
<!-- desc: rounded borders, soft adaptive colors, generous padding, subtle animation, glamour-rendered markdown -->

# DESIGN.md: Modern TUI (Charm-style)

The modern terminal look popularized by Charm (Glow, Gum, Soft Serve): rounded borders, soft adaptive colors that suit light
and dark terminals, generous padding, gentle spinners and markdown rendered with care. Friendly, polished, still fast.

## Principles

- **Friendly, not loud**: soft colors, rounded corners, breathing room.
- **Adaptive**: every color has a light and a dark variant chosen from the terminal background.
- **Guided**: inline help, clear prompts and forms that tell you what to do next.
- **Polish in motion**: spinners and small transitions show life without slowing anything.
- **Readable docs**: markdown is rendered (headings, code, lists), not dumped.

## Color

| Token | Light terminal | Dark terminal | ANSI 16 fallback | Use |
| --- | --- | --- | --- | --- |
| `fg` | `#1A1A1A` | `#DDDDDD` | default | Text |
| `muted` | `#8A8A8A` | `#6C6C6C` | 8 | Hints, help |
| `primary` | `#7D56F4` | `#9B7CFF` (approx.) | 5 | Titles, focus, selection |
| `secondary` | `#EE6FF8` | `#F78CFF` (approx.) | 13 | Highlights, badges |
| `success` | `#02BA84` | `#04D99A` (approx.) | 2 | Done |
| `warning` | `#C99700` (approx.) | `#F2C94C` (approx.) | 3 | Attention |
| `danger` | `#E0245E` (approx.) | `#FF5F87` | 1 | Errors |
| `surface` | `#F2F0FA` (approx.) | `#2A2438` (approx.) | none | Badges and selected items background |

- Adaptive colors via `lipgloss.AdaptiveColor{Light, Dark}`; background detected once at start.

## Typography

| Role | Style | Use |
| --- | --- | --- |
| Title | bold `primary`, often in a `surface` badge with 1-cell padding | Screen titles |
| Body | default | Text |
| Hint | `muted` | Inline help, placeholders |
| Key | bold | Shortcuts in the help view (`↑/k up • q quit`) |
| Markdown | Glamour `dark`/`light`/`auto` style | Docs, READMEs, long text |
| Icons | `✓ ✗ • → ●` (Unicode), Nerd Font icons optional | Status |

## Spacing and layout

- Unit = one cell; padding 1×2 (rows×cols) inside boxes; margins of 1 row between blocks.
- Minimum 80×24; centered content column of ≤ 100 cells on wide terminals; lists fill height.
- Help view at the bottom, one line short help, `?` toggles the full help.

## Shape and elevation

| Token | Glyphs | Use |
| --- | --- | --- |
| border-rounded | `╭─╮│╰╯` | Cards, panes, dialogs |
| border-thick-left | `▌` or `┃` in `primary` | Selected list item marker |
| badge | text on `surface` with 1-cell padding | Titles, tags |

- Elevation: focused pane gets a `primary` border; others `muted`. Dialogs are rounded boxes placed in the center (`lipgloss.Place`).

## Motion

| Token | Value | Use |
| --- | --- | --- |
| spinner | `spinner.Dot` / `spinner.MiniDot` (~10–12 fps) | Activity |
| progress | animated bar with spring easing (`bubbles/progress`), gradient `primary` → `secondary` | Determinate work |
| frame-budget | 30 fps | Animated components |
| transitions | none between screens | Instant |

- Reduced motion: progress bars jump to the value; spinners static.

## Components

- **Lists**: `bubbles/list` with title, filter (`/`), pagination dots, selected item with a `▌` marker and `primary` text.
- **Tables**: `bubbles/table`, header bold with bottom border, selected row in `surface`.
- **Forms**: `huh` forms: one question at a time or grouped, validation inline in `danger`.
- **Text input / text area**: placeholder in `muted`, focused prompt in `primary`.
- **Viewport**: scrollable markdown rendered by Glamour.
- **Status bar**: segments as colored badges (mode, file, position).
- **Help**: `bubbles/help` short and full views.
- **Empty/loading/error**: friendly sentence + icon (`• Nothing yet — press n to create one`), spinner + verb, `✗` + cause + next step.

## Accessibility

- Adaptive colors keep contrast on light and dark terminals; check `muted` stays ≥ 4.5:1 for anything important (approx.).
- `NO_COLOR`/`TERM=dumb`: Lip Gloss drops colors; borders and markers still show focus.
- Non-TTY: print plain output (Gum-style: results to stdout, UI to stderr).
- Keyboard: arrows and vi keys, `/` filter, `?` help, `esc` back, `q`/`ctrl+c` quit.

## Rules for agents

- Use Bubble Tea + Bubbles + Lip Gloss + Huh + Glamour; Ratatui equivalent: rounded `BorderType::Rounded`, `tui-input`, `tui-markdown` (approx.).
- Styles only in `styles.go` with `AdaptiveColor`; never a raw color in a view.
- Every screen has a short help line; every action is in the full help.
- Respect the terminal background: no full-screen background painting.
- Test with light and dark terminal themes, `NO_COLOR=1` and at 80×24.
