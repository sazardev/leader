<!-- name: Vim modal -->
<!-- desc: modal editor-like TUI: modes in the status line, hjkl, a command line, which-key style hints, buffers -->

# DESIGN.md: Vim modal

A keyboard-only TUI that behaves like a modal editor: NORMAL / INSERT / VISUAL / COMMAND modes shown in a status line,
hjkl navigation, a `:` command line and which-key style hints after a prefix key. For power-user tools (file managers,
mail, notes, git clients) whose users already think in Vim.

## Principles

- **Modes are always visible**: the status line says the mode in its own color; no hidden state.
- **Grammar over menus**: actions compose (`d` + motion, counts like `3j`).
- **Discoverable keys**: after a prefix, a hint panel lists what comes next.
- **The command line is the escape hatch**: everything is also a `:command` with completion.
- **Fast and quiet**: no animation on navigation; the screen changes only where the cursor acts.

## Color

| Token | ANSI 16 | 256 | Truecolor (dark) | Use |
| --- | --- | --- | --- | --- |
| `fg` | default | default | terminal default | Text |
| `bg` | default | default | terminal default | Never painted globally |
| `muted` | 8 | 244 | `#7C7F87` | Line numbers, hints' descriptions |
| `mode-normal` | reverse 4 (blue) | 75 | `#5F87FF` | NORMAL chip |
| `mode-insert` | reverse 2 (green) | 114 | `#87D787` | INSERT chip |
| `mode-visual` | reverse 5 (magenta) | 176 | `#D787D7` | VISUAL chip and selection |
| `mode-command` | reverse 3 (yellow) | 221 | `#FFD75F` | COMMAND chip |
| `cursorline` | 0 (black) bg / reverse in 16 | 236 | `#2A2D33` | Current row |
| `search` | reverse 3 | 221 | `#FFD75F` | Search matches |
| `error` | 1 | 203 | `#FF5F5F` | Command errors |
| `key` | bold 6 (cyan) | 45 | `#5FD7FF` | Keys in hints |

`NO_COLOR`: modes as text `-- INSERT --`, selection and cursorline as reverse video.

## Typography

| Role | Style | Use |
| --- | --- | --- |
| mode chip | bold, uppercase, 1 cell padding (`␣NORMAL␣`) | Status line left |
| title | bold | Pane titles |
| text | default | Content |
| line number | `muted`, right-aligned in a 4-cell gutter | Lists and buffers |
| hint key | `key` | Which-key panel |
| hint desc | default; groups `+name` in `mode-visual` color | Which-key panel |
| message | default / `error` | Command line messages |

## Spacing and layout

- Minimum 80×24. Rows: content (all but 2), status line (1), command line (1).
- Splits: vertical/horizontal panes separated by `│` / `─`; the focused pane's status line is full color, others `muted`.
- Which-key panel opens at the bottom above the status line, 3–8 rows, columns of `key → desc` 24 cells wide.
- Gutter 4 cells; content padding 1 cell.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| `split` | `│` `─` (ASCII `|` `-`) | Pane borders |
| `float` | rounded `╭─╮│╰─╯` | Pickers, confirmations |
| `statusline` | full-width row, mode chip + segments separated by `│` | Status |
| `selection` | `mode-visual` background / reverse | Visual selection |

## Motion

| Token | Value |
| --- | --- |
| `hint-delay` | 400ms after a prefix key (like `timeoutlen`) |
| `message-ttl` | 4s for info, until next key for errors |
| `spinner` | braille 80ms, only in the status line while a job runs |

- No animation for movement or scrolling (instant); smooth scroll optional and off by default.
- Reduced motion: spinner replaced by `…`.

## Components

- **Status line**: mode chip, buffer/item name, modified marker `[+]`, position `12/340`, right side: filters, job spinner.
- **Command line**: `:` prompt with completion (Tab cycles, a popup lists matches), history with ↑/↓, `Esc` cancels.
- **Which-key hints**: after `Space` (leader) or `g`, `z`, `[`, `]`; groups shown as `+files`.
- **Lists/buffers**: `j`/`k`, `gg`/`G`, counts, `/` search with `n`/`N`, `v` visual selection, `dd` delete (with undo `u`).
- **Pickers**: fuzzy finder float (`Space f`), Enter opens, `Ctrl-v`/`Ctrl-x` split.
- **States**: empty buffer (`~` filler lines + hint "press i to start" ), loading (status spinner), error (command line in `error`).

## Accessibility

- Every action reachable by keyboard and by a `:command`; `:help` lists all keys.
- Mode always shown as text (not only color); errors are text in the command line.
- Arrow keys work alongside hjkl; `Esc` always returns to NORMAL.
- Configurable keymap file; no time-critical sequences (hints wait).

## Rules for agents

- Model state as an explicit mode enum; every key handler is (mode, key) → action.
- Keymaps live in one table that also feeds the which-key panel and `:help` (one source of truth).
- Every destructive action is undoable (`u`) or asks in the command line.
- Status line and command line are always rendered, even in errors.
- Render through a diffed frame; never clear the screen per keystroke.
