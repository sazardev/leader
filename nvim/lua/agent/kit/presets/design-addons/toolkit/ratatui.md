<!-- name: Ratatui -->
<!-- desc: the design in Ratatui terms: one Theme struct, Layout with Flex::Center, bordered Blocks, Spans per cell -->
<!-- for: tui -->
<!-- default: rust -->

## Toolkit

| Design | Ratatui |
| --- | --- |
| Color token | a field of one `Theme` struct (`Color::Indexed(n)` or `Color::Reset` when the theme inherits the terminal, `Color::Rgb` for gradients) |
| Text style | one `Style` per role on the `Theme` (`title`, `muted`, `key`, `error`…); widgets take them, never build their own |
| Frame | `Block::bordered().border_type(BorderType::Rounded)` (`Plain`, `Thick`, `Double`, `QuadrantInside`…) + `.border_style(theme.border)` + `.title(...)` |
| Spacing | `Block::padding(Padding::new(l, r, t, b))`; `Layout::spacing(n)` between areas |
| Layout | `Layout::vertical([Constraint::Length(n), Constraint::Fill(1), …]).areas(area)`; columns with `Layout::horizontal` |
| Centering | a layout with `.flex(Flex::Center)` on both axes around a `Constraint::Length` box |
| Width | `Line::width()` / `unicode-width` for display width; never `str::len` |
| Size | `frame.area()` on every draw; nothing is laid out from a constant |
| Grid / keypad | nested horizontal layouts of equal `Constraint::Length` cells; the focused cell's block uses `theme.focus` |
| Overlays | `Clear` first, then the popup's block in a centered area |
| Gradients / art | one `Span` per character with its own `Style::fg(Color::Rgb(..))` |
| Motion | a tick event in the event loop drives frames; effects with `tachyonfx` when the design asks for them (approx.: verify before adding) |

- The draw function splits `frame.area()` into header, body and help bar first, then hands each area to one widget.
- A widget that does not fit its area renders its compact variant; test the 80×24 minimum with `TestBackend` and `insta` snapshots.

## Rules for agents

- Every color and style comes from the `Theme`; a widget never names a `Color` itself.
- Never pad with hand-counted spaces: areas come from `Layout`, widths from display width.
