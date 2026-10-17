<!-- name: Textual -->
<!-- desc: the design in Textual terms: tokens as TCSS variables, layout in a .tcss file, align and dock, snapshot tests -->
<!-- for: tui -->
<!-- default: python -->

## Toolkit

| Design | Textual |
| --- | --- |
| Color token | a TCSS variable in the app's theme (`$primary`, `$accent`, `$error`, `$foreground-muted`, or a custom `textual.theme.Theme` with `variables`) |
| Text style | a TCSS class per role (`.title`, `.muted`, `.key`, `.error`) |
| Frame | `border: round $primary;` (`solid`, `heavy`, `double`, `ascii`, `tall`…) + `border-title-align` |
| Spacing | `padding: v h;` inside, `margin: v h;` between widgets |
| Layout | `layout: vertical;` (or `horizontal`, `grid` with `grid-size` / `grid-columns`); `dock: top` / `dock: bottom` for header and footer |
| Centering | `align: center middle;` on the container |
| Size | `width`/`height` in cells, `fr` or `%`; `min-width` for the smallest usable layout |
| Grid / keypad | a `Grid` container (`grid-size: 4 5; grid-gutter: 1;`) of `Button`s; focus via `:focus` |
| Help bar | the built-in `Footer` with the screen's `BINDINGS` |
| Motion | `widget.styles.animate(...)` and `offset` transitions; respect `App.animation_level` |

- Styles live in `.tcss` files (`CSS_PATH`), never in Python strings; one file per screen plus a shared one.
- Test screens with `pytest-textual-snapshot` (`snap_compare`) at 80×24 and at the largest size the spec names.

## Rules for agents

- Every color comes from a theme variable; a widget never sets a hex value.
- Layout is TCSS (`align`, `dock`, `grid`); no manual spacing with blank labels.
