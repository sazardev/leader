# Undo, clipboard and yank history (`<leader>u`)

Undo and paste behave closer to VS Code without changing how Vim works underneath. Nothing runs in the background,
and nothing is loaded until you use it. Keys: [`CHEATSHEET.md`](../../CHEATSHEET.md) (sections **History** and **Clipboard**).

## Undo word by word

In plain Vim, `u` undoes a whole insert at once: type a paragraph, press `u`, and all of it is gone. Here one insert
becomes several undo steps. A new step starts:

- after each space or tab (one `u` = one word),
- after a new line (Enter, a snippet that adds lines, a paste),
- after a pause in typing (`settings.history.pause_ms`, 1 s by default).

`.` still repeats the **whole** insert, and a macro's insert is still a single step. To get Vim's behaviour back, turn
off **Undo word by word** in the settings panel (`<leader>Sp`) or set `history.word_undo = false`.

| Key | What it does |
|---|---|
| `u`, `Ctrl+Z` | undo; the lines that changed glow for a moment |
| `Ctrl+R`, `U`, `Ctrl+Y` | redo |
| `Ctrl+Z` in insert mode | undo without leaving insert mode |

`Ctrl+Z` never suspends nvim. `U` replaces Vim's rarely used "undo line", and `Ctrl+Y` replaces "scroll one line up".
`history.redo_keys = false` keeps Vim's meanings.

## Going back in time

- `<leader>uu` opens the **undo tree** (Neovim's built-in `:Undotree`) in a side panel. Moving the cursor in it moves the file
  through its history, branches included (what you undid and then overwrote is still there). `q` closes it.
- `<leader>u[` / `<leader>u]` take the file to how it was at the **previous / next save** (`:earlier 1f` / `:later 1f`). This is VS
  Code's Timeline, and it is undoable too: `<leader>u[` then `u` gets your edits back.

Undo history is saved with the file (`undofile`), so all of this works after you restart nvim.

## The clipboard keeps what you copied

With `settings.clipboard.keep` (on by default), only **`y` (copy) and `d` (cut)** fill the clipboard:

- `x`, `X`, `c`, `C` delete without copying (changing a word does not lose what you copied);
- pasting over a selection (`viw` then `p`) keeps the clipboard, so you can paste the same text again over the next one.

An explicit register still works as usual: `"ax` puts the character in register `a`. `<leader>d` deletes without copying
with any motion. Turn it off with **x / c keep the clipboard** in the settings panel.

## Yank history

Every copy and cut is kept, newest first, without duplicates. The list survives restarts
(`stdpath("state")/yanks.json`).

- **Right after `p` / `P`**, `[y` swaps what you pasted for the previous copy, and `]y` goes back to a newer one. The count and
  `p`/`P` are kept, and your registers are not touched.
- `<leader>uy` lists them all with a preview. Enter pastes the copy after the cursor and makes it the clipboard again, so the
  next `p` repeats it. `<C-x>` forgets one entry, and `<leader>ux` clears the whole list.

Settings: `history.yanks.max` (50 entries), `max_chars` (longer texts are not kept), `persist` (false = memory only).

## Pitfalls

- **WSL / SSH: text copied outside nvim.** Copying from nvim reaches the system clipboard (OSC 52). Pasting from the system
  clipboard is **Ctrl+Shift+V** in the terminal, because the terminal does not let nvim read it (`p` pastes nvim's own clipboard).
- `[y` only works right after a paste. Once anything else changes the buffer it tells you to paste first.
