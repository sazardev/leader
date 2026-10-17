<!-- name: Charm (Lip Gloss) -->
<!-- desc: the design in Bubble Tea + Lip Gloss terms: one styles file, Place to center, Join to compose, Harmonica -->
<!-- for: tui -->
<!-- default: go -->

## Toolkit

| Design | Lip Gloss / Bubble Tea |
| --- | --- |
| Color token | one `lipgloss.AdaptiveColor{Light, Dark}` (or an ANSI index string `"4"` when the theme inherits the terminal) per token, in `styles.go` |
| Text style | one named `lipgloss.Style` per role (`Title`, `Muted`, `Key`, `Error`…), built once, never inline in a view |
| Frame | `.Border(lipgloss.RoundedBorder())` (or `NormalBorder`, `ThickBorder`, `DoubleBorder`, `BlockBorder`, `HiddenBorder`) + `.BorderForeground(token)` |
| Spacing | `.Padding(v, h)` inside frames, `.Margin(v, h)` between blocks; one cell is the unit |
| Layout | `lipgloss.JoinVertical` / `JoinHorizontal` compose blocks; `lipgloss.Place(width, height, lipgloss.Center, lipgloss.Center, view)` centers the whole screen |
| Width | `lipgloss.Width(s)` / `lipgloss.Height(s)` measure rendered blocks (display width, ANSI ignored); never `len(s)` |
| Size | the last `tea.WindowSizeMsg` is kept in the model; every view is laid out from it, never from a constant |
| Grid / keypad | a row of fixed-width cells (`.Width(n).Align(lipgloss.Center)`) joined horizontally; the focused cell gets the `Focus` style |
| Tables / lists | `lipgloss/table` for static tables, `bubbles/table` and `bubbles/list` for interactive ones |
| Help bar | `bubbles/help` + `bubbles/key` bindings; `help.Width = width` so it truncates with `…` instead of overflowing |
| Motion | `tea.Tick` for frames; `github.com/charmbracelet/harmonica` springs for eased values (position, flash fade) |

- The root view ends with `lipgloss.Place(...)` over the full window, so the composition is centered and never touches the edges by accident.
- Compose top-down: header, body, help bar as three blocks joined vertically; each block renders to exactly the width it was given.
- A block that does not fit swaps to its compact variant (smaller banner, fewer columns); test the 80×24 minimum with `teatest` golden files.
- Golden tests force a color profile (`lipgloss.SetColorProfile(termenv.Ascii)` or the `teatest` option) so snapshots do not depend on the terminal.

## Rules for agents

- Read every color and style from `styles.go`; a view only calls styles and `lipgloss.Join*` / `Place`.
- Never pad with hand-counted spaces: widths come from `lipgloss.Width` and `.Width(n)`.
