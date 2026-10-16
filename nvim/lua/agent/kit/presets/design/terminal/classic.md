<!-- name: Classic terminal -->
<!-- desc: Unix/curses tradition: line-drawing borders, ANSI 16 only, function-key help bar, works over SSH and serial -->

# DESIGN.md: Classic terminal

The curses tradition (htop, mc, mutt, vim): line-drawing borders, 16 ANSI colors, a function-key help bar and keyboard
habits people already have. It works on any terminal, over SSH and serial consoles, in tmux and screen, with any font.

## Principles

- **Familiar beats novel**: follow the conventions of htop, mc and vi; users should guess keys right.
- **Works everywhere**: ANSI 16 colors and VT100 line drawing only; no truecolor, no Unicode beyond box drawing.
- **Keyboard first**: every action has a key; function keys and vi/emacs motions both work.
- **Stable layout**: panels do not move; information appears in fixed places.
- **Low bandwidth**: redraw only what changes; usable at 9600 baud.

## Color

| Token | ANSI 16 | Use |
| --- | --- | --- |
| `fg` | 7 (white) / default | Text |
| `bg` | default (or 4 blue for full-screen apps in the mc style, approx.) | Background |
| `title` | 6 (cyan) bold | Panel titles |
| `selection` | 0 on 6 (black on cyan) | Selected row |
| `key` | 0 on 6 (black on cyan) | Function key labels in the help bar |
| `muted` | 8 | Secondary text |
| `success` | 2 | OK, running |
| `warning` | 3 | Attention |
| `danger` | 1 | Errors |
| `info` | 4 | Links, info |

- Only the 16 ANSI colors; meaning never depends on the exact shade the terminal theme gives them.

## Typography

| Role | Style | Use |
| --- | --- | --- |
| Body | default | Text |
| Title | bold | Panel titles, headers |
| Key | `F1`…`F10`, `^X`, `M-x` notation | Help bar and menus |
| Emphasis | bold or underline | Hotkey letters in menus (`&File` → underlined F) |
| Disabled | dim | Unavailable items |

- One monospace cell per character; no wide glyphs.

## Spacing and layout

- Unit = one cell; panels share borders (no gaps); padding 1 cell inside panels.
- Minimum 80×24 (the VT100 size); everything must fit there. Wider terminals widen the main panel only.
- Fixed regions: optional menu bar (row 1), content, status line (row n-1), function-key help bar (row n).
- Two-pane layouts (mc style) split 50/50 and keep their split on resize.

## Shape and elevation

| Token | Glyphs | Use |
| --- | --- | --- |
| border | `┌─┐│└┘├┤┬┴┼` (VT100 ACS) with `+-|` fallback | Panels, tables |
| border-double | `╔═╗║╚╝` | Dialogs |
| separator | `─` | Inside panels |

- Elevation: dialogs are double-bordered boxes over the content, with a 1-cell shadow in `muted` (dark cells) to the right and below.

## Motion

| Token | Value | Use |
| --- | --- | --- |
| spinner | `|/-\` 4 frames, 125 ms | Activity |
| refresh | 1–2 s for live data | Monitors (htop style) |
| transition | none | Instant screen changes |

- No animation beyond spinners and live refresh; reduced motion shows a static `*`.

## Components

- **Menu bar** (optional): `File Edit View Help`, opened with F9 or Alt+letter.
- **Panels**: bordered, title in the top border (`┤ Files ├`).
- **Lists/tables**: column headers in bold, selected row black on cyan, sort column marked with `▲`/`▼` or `^`/`v`.
- **Status line**: path, counts, mode.
- **Help bar**: `1Help 2Save 3View 4Edit … 10Quit`, numbers in the `key` style (mc/htop style).
- **Dialogs**: double border, title, buttons `< OK >` `< Cancel >`, Tab moves, Enter confirms, Esc cancels.
- **Prompts**: one line at the bottom (`Search: `), Esc cancels.
- **Progress**: `[######....] 60%`.
- **Empty/loading/error**: message in the status line; errors in a dialog with the cause.

## Accessibility

- `NO_COLOR`: selection by reverse video, titles by bold; layout unchanged.
- Works with screen readers that follow the cursor: the cursor sits on the selected item.
- Keys: F-keys plus alternatives (`Esc 1`…`Esc 0` for terminals without F-keys, `^C`/`q` to quit, `/` to search, `?` help).
- No reliance on mouse; mouse support optional.

## Rules for agents

- ANSI 16 colors only; never truecolor or 256 colors.
- Use line drawing with an ASCII fallback (`+-|`) when the terminal does not support it (`TERM=vt52`, `LANG=C`).
- Bubble Tea/Lip Gloss: `lipgloss.NormalBorder()` / `DoubleBorder()`, colors as `lipgloss.Color("6")`. Ratatui: `BorderType::Plain`/`Double`, `Color::Indexed(n)` or the named 16.
- Every action has a key and appears in the help bar or `?` help screen.
- Test at 80×24, in tmux, over SSH with `TERM=xterm` and `TERM=vt100`.
