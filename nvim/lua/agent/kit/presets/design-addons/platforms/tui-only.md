<!-- name: Terminal only -->
<!-- desc: a full-screen TUI: 80x24 minimum, resize at any time, works over SSH and in tmux, no mouse required -->
<!-- for: tui -->
<!-- default: tui -->

## Spacing and layout

- Designed for 80×24 cells and usable down to it; above 120 columns a second pane may appear.
- Redraw on every resize (`SIGWINCH`); nothing is cut silently: truncate with `…` and keep the key column readable.
- Runs the same over SSH, in tmux/screen and in the alternate screen; restores the terminal on exit, crash or `Ctrl+C`.

## Components

- Keyboard first: arrows and `hjkl`, `Enter` select, `Esc` back, `q` quit, `/` search, `?` help; the mouse is an optional extra.
- A status/help line shows the keys that matter on the current screen.

## Rules for agents

- Test at 80×24, at 200×60 and while resizing; test inside tmux and over SSH.
- Never assume a font, a color depth or mouse support: detect and degrade.
