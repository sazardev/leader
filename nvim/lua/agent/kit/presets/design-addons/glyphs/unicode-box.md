<!-- name: Unicode boxes and braille -->
<!-- desc: box drawing, block elements and braille dots for borders, bars, charts and sub-cell graphics -->
<!-- for: tui -->
<!-- default: tui -->

## Typography

- Borders with box drawing: light `┌─┐│└┘`, rounded `╭─╮│╰╯`, heavy `┏━┓┃┗┛` for focus, double `╔═╗║╚╝` for dialogs.
- Bars and meters with block elements `▁▂▃▄▅▆▇█` (vertical) and `▏▎▍▌▋▊▉█` (horizontal); sparklines with the vertical set.
- Charts and fine graphics with braille (U+2800-U+28FF): 2×4 dots per cell, 8× the resolution of plain cells.

## Rules for agents

- Every glyph has an ASCII fallback (`+-|`, `#`, `*`) selected when the locale is not UTF-8.
