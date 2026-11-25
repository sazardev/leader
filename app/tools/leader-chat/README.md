# leader-chat

An isolated [OpenTUI](https://opentui.com/) chat TUI for Leader. It displays an atomic JSON snapshot and writes atomic JSON commands; it never runs a model, starts an agent, or edits project files.

The crate is deliberately not a member of `app/Cargo.toml`'s workspace. It declares its own `[workspace]` and does not change the desktop app or any Lua configuration.

## Requirements and setup

- Rust 1.88 or newer.
- `curl`, `unzip`, and `sha256sum` (or `shasum` on macOS).

From the repository root:

```sh
make chat
```

Or build the crate directly:

```sh
cd app/tools/leader-chat
./scripts/fetch-opentui.sh
cargo build --locked
```

The script detects Linux/macOS x64/arm64, downloads the official `opentui-native-v0.9.9-<platform>.zip`, verifies its pinned SHA-256, and extracts it to `vendor/opentui-native`. `./scripts/fetch-opentui.sh --all` also downloads and verifies all four supported archives, keeping copies in `vendor/opentui-archives/`. `.cargo/config.toml` resolves `OPENTUI_LIB_DIR` relative to the crate. `vendor/` and `target/` are generated and ignored.

## Use

```sh
./target/debug/leader-chat \
  --state /tmp/leader-chat-state.json \
  --commands /tmp/leader-chat-commands.json
```

Both paths are required and must be different. The state producer and command consumer are owned by Leader; this tool only speaks their JSON protocol. On Unix, command files are created with `0600` permissions because they contain conversation text.

Keys:

| Key | Action |
| --- | --- |
| `Ctrl-S` | Send the composer (blank drafts are ignored) |
| `Ctrl-C` | Ask Leader to stop streaming; does not quit |
| `Ctrl-N` | Ask Leader for a new session and clear the draft |
| `Ctrl-H` | Request history and open the session picker |
| `Ctrl-M` | Open the model picker |
| `Ctrl-P` | Open the profile picker |
| `Ctrl-G` | Close a picker without quitting |
| `Ctrl-Q` | Quit cleanly (the chat session keeps running in Leader) |
| `Enter` | Insert a newline in the composer |
| `Tab` / `Shift-Tab` | Move focus between composer, transcript, and picker |
| `Esc` | Close a picker; does not quit |

The transcript is a sticky-bottom `ScrollBox`: it follows new output while at the bottom and stays put after scrolling up. Its body uses OpenTUI 0.9.9's native `Markdown` widget (CommonMark/GFM, fenced code, tables, links, and task lists). Thinking, errors, state, and usage are rendered alongside their message. OpenTUI 0.9.9 calls its multiline editor `Textarea`; `Input` is single-line, so the multiline composer uses `Textarea`.

## State protocol

The state file must be replaced atomically by its producer. Times are epoch milliseconds. Unknown message roles and arbitrary JSON `usage` objects are preserved.

```json
{
  "version": 1,
  "pid": 123,
  "cwd": "/project",
  "updated_at": 1700000000000,
  "session": {
    "id": "session-1",
    "title": "Refactor the parser",
    "model": "model-a",
    "profile": "profile-a",
    "effort": "high",
    "running": true
  },
  "messages": [
    {
      "id": "message-1",
      "role": "assistant",
      "text": "Hello **world**",
      "thinking": "Checking the parser.",
      "at": 1700000000000,
      "state": "streaming",
      "usage": { "input": 12, "output": 4 },
      "error": null
    }
  ],
  "profiles": [{ "id": "profile-a", "label": "Careful" }],
  "models": [{ "id": "model-a", "label": "Model A" }],
  "history": [
    { "id": "session-0", "title": "Older chat", "at": 1699999990000, "model": "model-a" }
  ],
  "ack": { "id": "123-1700000000000-0", "ok": true }
}
```

`thinking`, `state`, `usage`, `error`, `session.effort`, and `ack` may be omitted or null. A poll runs every 100 ms on a worker thread, coalesces overlapping reads, and accepts at most 16 MiB. A missing, malformed, oversized, or unsupported snapshot preserves the last valid state and reports the error in the status line. `ack` confirms whether Leader accepted a command; a rejection is shown without silently losing the command status.

## Command protocol

Commands are compact JSON objects with a process-unique id. Unused optional fields are omitted. The writer serializes a FIFO on a worker thread, writes and `sync_all`s a sibling temporary file, then atomically renames it over `--commands`. On exit it drains pending writes for up to two seconds.

```json
{
  "version": 1,
  "id": "123-1700000000000-0",
  "action": "send",
  "text": "Please review this function"
}
```

Supported actions:

| Action | Payload |
| --- | --- |
| `send` | `text` |
| `stop` | none |
| `new` | none |
| `history` | none |
| `select_session` | `session_id` |
| `set_model` | `value` |
| `set_profile` | `value` |

The single command file has no acknowledgement channel. The consumer should drain it promptly; atomic replacement guarantees it always sees one complete JSON object, not a partial write. The writer waits for the consumer to remove the file before publishing another queued command, so rapid actions cannot overwrite an unread command.

## Checks

```sh
cargo fmt --all -- --check
cargo test --locked
cargo clippy --locked --all-targets -- -D warnings
```

Tests cover schema parsing, bounded atomic reads, flat command serialization, atomic command replacement, and `TestApp` rendering, multiline send, stop, new session, history/model/profile selection, quit behavior, resize, and 100 ms snapshot polling.

## Packaging note

This is a prototype and is not installed or shipped with `leader` yet. OpenTUI's native library bundles FFmpeg (LGPL-2.1-or-later) and other third-party components. A future packaged binary must include the license notices from the native archive and satisfy the corresponding distribution requirements.
