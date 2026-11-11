# Terminal

`<leader>T` menu. The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md).

## The mental model

There are two kinds of terminal, and both survive `Esc`:

- **The command terminal** (toggleterm #1): every language menu and Makefile task runs here. One shared
  place, so the next command always lands where you look. Re-running a command reuses it.
- **Named terminals**: `http test` (`<leader>ch` curls) and `noodle` (`<leader>cNo` TUI) live apart, so firing
  requests never types into your running app.
- **Your own shells** (`<leader>Tn`): as many as you want, for git, curl, whatever.

`Esc` never kills anything: it closes the window and the shell (and whatever runs in it) keeps going.

## Keys

| What | Keys |
|---|---|
| Show / hide the command terminal (reopen after `Esc`, sends nothing) | `<leader>Tt` |
| List every terminal and jump to it (`Enter`) | `<leader>Tl` |
| New shell | `<leader>Tn` |
| Ctrl-C to the terminal under the cursor (else the command one, when it runs something) | `<leader>Ts`, or `Ctrl+C` inside it |
| The floating terminal (same key closes and reopens) | `Alt+i` |
| A vertical / horizontal terminal split | `<leader>Tv` / `<leader>Th` |
| Close the window, keep everything running | `Esc` (in the terminal or its Normal mode) |
| Unfocus: back to the code, terminal stays open | `Shift+Esc` |
| Leave terminal mode (then `i` types again, `Esc` closes) | `Ctrl+x` |
| Kill the shell itself | `Ctrl+D` or `exit` |

Inside a terminal you are in *terminal mode*: everything you type goes to the shell. `Ctrl+x` takes you to
Normal mode (move, copy output with `y`, search with `/`); `i` goes back to typing. Window navigation
(`Ctrl+h/j/k/l`) works from Normal mode, or unfold with `Shift+Esc` first.

## Workflows

- **Running from a menu** (`<leader>gr`, a language `run`, a Makefile target): the command terminal keeps the
  focus, in terminal mode, so you see the output and can answer a prompt. `Esc` closes it (the command keeps
  running); the next command reuses the same terminal.
- **A command is running** (`dotnet run`, `noodle` TUI): `Esc` hides it, `<leader>Tt`/`<leader>Tl` (or the
  action that opened it) brings it back. Nothing restarts, nothing is typed into it by reopening.
- **Run something else meanwhile**: `<leader>Tn` opens a second terminal; `<leader>Tl` jumps between them.
- **It hangs**: `<leader>Ts` (or focus it and `Ctrl+C`).
- **Task output to quickfix**: `<leader>Rq` reads the last terminal with the agent's error parser
  (`<leader>ao` reads it for the agent's "fix from output").
- **Paste into the terminal**: `Ctrl+Shift+V` (the terminal does not see nvim's clipboard, so `p` pastes
  nvim's own yank, not the system's).

## Pitfalls

- **Re-running a command while its terminal is busy types into the running process.** That is how the
  terminal works (toggleterm sends keys); the menus that must not do that (`noodle` TUI) check first and
  just focus. When in doubt, `<leader>Tn` for the new command.
- **Terminals and panes share the screen, not the keys**: `Alt+i` is the floating terminal; `Alt+v` / `Alt+h` open
  a **pane** with the start screen (see [panes.md](panes.md)), so a vertical / horizontal terminal is
  `<leader>Tv` / `<leader>Th`. The shared toggleterm command terminal (`<leader>Tt`, where every language and task
  command runs) and the named terminals (`http test`, `noodle`) live apart from both. `<leader>Tl` lists all of them.
- A terminal that finished (`[process exited]`) is closed with `Esc` like any other; a dead entry never
  comes back in `<leader>Tl`.
