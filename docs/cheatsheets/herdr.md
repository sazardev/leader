# Herdr (`<leader>W`)

[Herdr](https://herdr.dev) is the terminal workspace that runs the coding agents: every agent lives in a real pane with
its shell, its logs and its process. Leader talks to it through its CLI, so you can **see what every agent in the
workspace is doing** without leaving the editor, and Herdr can see what **your** nvim is doing.

Keys: [`CHEATSHEET.md`](../../CHEATSHEET.md) (section **Herdr**). Nothing here costs tokens: it only reads.

## The panel (`<leader>Wa`)

The breakdown of the workspace:

- **One row per agent**, grouped by workspace: its state (`● working`, `○ idle`, `! blocked`, `✓ done`), the agent
  (`opencode`, `claude`, `codex`…) and where it is (`~/Work/leader`).
- **The pane on the right** is the agent under the cursor: its own words (the transcript of its terminal) and **why
  Herdr thinks it is in that state** (the detection rule that matched, e.g. `progress_bar_working`).
- It **refreshes on its own** every `herdr.observe_ms` (2 s), so the state you read is the state now.

| Key | Does |
|---|---|
| `j` `k` | move |
| `Enter` | read the agent under the cursor |
| `f` | bring its pane to the front in Herdr |
| `s` | send it a prompt (the text you type is submitted to it) |
| `x` | the report of how Herdr detected its state |
| `r` | refresh now |
| `q` | close |

An agent that is **working** can only be read as it is drawn on screen (its scrollback is only captured when it goes
idle), so the panel shows the visible screen then and the transcript once it settles.

## Setup (`<leader>Ws`)

What Herdr is on this machine, and what to do about it:

- The **binary**: not installed? The setup offers to install it (`curl -fsSL https://herdr.dev/install.sh | sh`, the
  PowerShell one on Windows) in a floating terminal. Nothing is installed without pressing the button.
- The **server**: running or not, its version, its socket.
- **This nvim**: whether it is inside a Herdr pane, and whether it registers itself as an agent (see below).
- The **integrations**: `herdr integration install <agent>` makes an agent (Claude, OpenCode, Codex…) report its own
  state to Herdr and come back after a server restart. The setup lists the ones that are missing or need repair.

## Settings (`<leader>Sp` → Herdr)

| Setting | What it does |
|---|---|
| **Herdr** | `auto` (the binary decides), `on`, `off` |
| **Register as an agent** | `auto` (inside Herdr), `on`, `off` |
| **Setup** | the menu above |

In `lua/local.lua`:

```lua
return { herdr = { enabled = "auto", register = "auto", observe_ms = 2000, lines = 150 } }
```

The old knob still works: `session = { herdr = true }` (or `false`) in `local.lua` decides the registration when
`herdr.register` is left at `auto`.

## nvim as an agent of the workspace

When Leader registers itself in Herdr (`register`), the pane shows up in Herdr's Agents panel **and says what it is
doing**: `working` while the inline agent runs (with the action's name), `blocked` while a proposal waits for you to
accept it, and `idle` when nothing runs. It never takes the pane from a real agent that already occupies it.

With `herdr >= 0.9.5` the registration also carries a **resume command** (`nvim +HerdrResume`, which restores the
folder's session), so Herdr brings the pane back with your session after the server restarts. Older versions (0.9.x)
do not know that option: the registration is made without it, so Herdr cannot bring the pane back — the panel says so.

## Handing work to another agent

`<leader>ag` (the agent menu) sends `file:range` + your instruction to an agent that is already running in a Herdr
pane, with the diagnostics of the range and the current code when the file has unsaved changes. It only appears
inside Herdr. See [agent.md](agent.md).
