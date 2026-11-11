# Panes

A **pane is a real Neovim window**, not a plugin. `Alt+V` opens one to the right and `Alt+H` one below with the
**start screen** in it; `ff` / `fo` from that screen load the chosen file **in that pane**. The window you were in keeps
its file, so you can work with two, three or more files at once and still have a dashboard in any of them.

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md) (the `Panes` group). This page is the workflow.

## The mental model

- **Every split is a pane.** No extra layer, no tabs: the same windows, buffers and LSP clients as always; sessions,
  diagnostics, the agent and the terminal work inside them without knowing they are in one.
- **The dashboard is per pane.** The start screen keeps one selection, one layout and one set of window options per
  window, so a dashboard in a narrow split shrinks itself and the one in the big split stays as it was. Several can be
  open at once; opening a file replaces only the dashboard of the pane it was opened from.
- **Search from the pane, land in the pane.** `Find File`, `Recent Files`, `Find Word` and the rest run in the window
  that owns the dashboard. Telescope opens its picker over the editor; choosing a file closes the picker and puts the
  file where the dashboard was.
- **The dashboard is not a mode.** Once a file is loaded the pane is a normal window: `Ctrl+h/j/k/l` moves, `:split`
  works, the file tree and the agent use it like any other.

## Keys and mouse

- `Alt+V` / `Alt+H`: new pane right / below with the start screen. They also work from terminal mode: they leave it
  and open the pane, so nothing gets typed into the running shell.
- `Alt+T`: a quick terminal pane below the current one (one shell per tab). `Esc` closes it and leaves you in the file
  in normal mode; `Alt+T` brings the same shell back. See [terminal.md](terminal.md).
- `Ctrl+h/j/k/l` (NvChad's window keys): move the focus. It also works from a terminal in Normal mode (`Ctrl+x`).
- `Alt+Left/Right/Up/Down`: make the current pane narrower / wider / shorter / taller. The same border can be dragged
  with the mouse when `mouse` is on. The step is a setting (`<leader>Sp` → Panes → Resize step).
- `Alt+Z`: zoom the pane (a tab of its own, keeping the real layout in the other tab); the same key comes back.
- `Alt+Q`: close the current pane. The last one stays; a buffer with unsaved changes is not thrown away.
- `<leader>VX`: close every other pane of the tab and keep the current one (buffers stay open).
- `<leader>V`: the menu with the same actions plus **list** (jump to a pane), **equal sizes**, **rotate** and
  **swap with next**. The desktop app's View › Panes has the same items.
- **Layout presets** (`<leader>V`): `2` two columns, `3` three columns, `m` a wide main pane with two stacked on the
  right, `4` a 2x2 grid. The file you are editing stays in the first pane and the new ones open on the start screen.
  On a tab that already has several panes it asks before replacing the layout; the buffers stay open, so unsaved work
  is never lost.
- **Terminals**: `Alt+I` is still the floating terminal; `Alt+V`/`Alt+H` no longer toggle terminals. Use `<leader>Tv` /
  `<leader>Th` for a vertical / horizontal terminal split, and `<leader>Tt` / `<leader>Tn` for the command terminal and
  a new shell.

## Workflows

- **Two files side by side**: `Alt+V`, then `ff` and pick the second file; the first pane keeps the file you were
  editing. `Alt+V` again from either pane adds a third. For a typical layout without opening panes one by one, use
  `<leader>V2`, `<leader>V3`, `<leader>Vm` or `<leader>V4`.
- **A dashboard that stays**: open the dashboard with `Alt+V` and use the **other** pane to edit. When you want another
  file, go back to the dashboard pane and pick it; the pane you were editing is untouched.
- **A full-screen look**: `Alt+Z` on the pane you are reading, `Alt+Z` again to return to the split.
- **A pane that got too narrow**: `Alt+Right` a few times, or `<leader>V=` to make them all equal.
- **Find a pane**: `<leader>Vl` lists every pane with its file, size and whether it has unsaved changes; Enter focuses
  it.
- **The pane list also shows terminals and the tree**: they are windows too; entering one just moves the focus.

## Pitfalls

- **A pane is not a tab.** Tabs are not shown (`showtabline = 0`) and are only used by `Alt+Z`; `:tabnew` is still
  Neovim's own thing and is not what the pane keys use.
- **A terminal pane is not killed by closing its window.** `Alt+Q`/`Esc` close the window and the shell keeps running;
  `<leader>Tl` lists it and brings it back.
- **The start screen does not survive a session restore as a dashboard.** It is an unlisted scratch buffer; sessions
  save the windows and the files, and a dashboard pane comes back empty (open it again with `Alt+V` or `<leader>Vd`).
- **A terminal pane comes back as a fresh shell.** Sessions include terminals (`terminal` in `sessionoptions`): the
  window, its place and its working directory return, but the scrollback and whatever was running do not. The session is
  saved on exit and every minute (`<leader>Sp` → Editing → Session autosave), and a bare `leader` inside a project
  (or `leader <folder>`) restores it automatically; `<leader>Px` skips saving that run.
- **Resizing is per window, not per column.** `Alt+Left`/`Alt+Right` change the current window's width; the neighbor
  gets the difference. If the pane is already at the minimum, nothing moves.
