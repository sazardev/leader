<!-- name: ASCII only -->
<!-- desc: pure 7-bit ASCII: works on any terminal, serial console, log file and screen reader -->
<!-- for: tui -->
<!-- default: classic -->

## Typography

- Only printable ASCII: borders `+-|`, bullets `*` and `-`, checkboxes `[x]`/`[ ]`, radios `(*)`/`( )`, arrows `->`, progress `[#####-----]`.
- Emphasis by case, brackets and spacing, never by special characters.

## Rules for agents

- No character above U+007E in UI strings; a test fails on any non-ASCII byte in rendered frames.
