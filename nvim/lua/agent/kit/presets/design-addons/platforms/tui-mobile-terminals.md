<!-- name: Narrow terminals -->
<!-- desc: phone terminals (Termux, Blink, a-Shell) and split panes: layouts that work from 40 columns -->
<!-- for: tui -->

## Spacing and layout

- Usable from 40×20 cells: a single column, no side-by-side panes below 60 columns.
- Labels shorten before content does (`Downloads` → `DL`); tables drop low-priority columns first, by a declared priority.

## Components

- Every key binding has a single-key or `Ctrl` alternative (soft keyboards lack `Alt`/function keys); touch scrolling works where the terminal sends mouse events.

## Rules for agents

- Test at 40×20 and at 60×24 as well as 80×24.
