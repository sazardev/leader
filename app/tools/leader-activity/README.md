# leader-activity

An isolated [OpenTUI](https://opentui.com/) prototype that displays Leader's atomic JSON activity snapshot. It is not a member of the desktop app's workspace: this crate declares its own `[workspace]` and does not modify `app/Cargo.toml` or `app/Cargo.lock`.

## Requirements and setup

- Rust 1.88 or newer.
- `curl`, `unzip`, and `sha256sum` (or `shasum` on macOS).

From the repository root:

```sh
make activity
```

Or build the crate directly:

```sh
cd app/tools/leader-activity
./scripts/fetch-opentui.sh
cargo build --locked
```

The script detects Linux/macOS x64/arm64, downloads the official `opentui-native-v0.9.9-<platform>.zip`, verifies its pinned SHA-256, and extracts it to `vendor/opentui-native`. `./scripts/fetch-opentui.sh --all` also downloads and verifies all four supported archives, keeping copies in `vendor/opentui-archives/`. `.cargo/config.toml` resolves `OPENTUI_LIB_DIR` relative to the crate. `vendor/` and `target/` are generated and ignored.

## Use

```sh
./target/debug/leader-activity --file /path/to/leader-activity-PID.json
./target/debug/leader-activity --help
```

Keys: `1` all, `2` running, `3` terminal, `f` follow newest, `r` refresh, `q` or `Esc` quit. `j/k` and the arrow keys move the selection.

The expected schema is:

```json
{
  "version": 1,
  "pid": 123,
  "cwd": "/project",
  "updated_at": 1700000000000,
  "running": [],
  "events": []
}
```

Each item uses `id`, `seq`, `name`, `state`, `started_at`, `updated_at`, and the optional `finished_at`, `title`, `message`, `target`, and `percent`. Times are epoch milliseconds. The terminal filter shows all finished events, including failures; the summary separates Done and Failed.

The UI uses the terminal's colors. A worker reads at most 8 MiB per cycle; `app.set_interval` polls every 500 ms and coalesces concurrent reads, so file I/O stays off the UI thread. An invalid snapshot preserves the last valid one and shows the error in the status line.

## Checks

```sh
cargo fmt --all -- --check
cargo test --locked
cargo clippy --locked --all-targets -- -D warnings
```

Pure formulas and state transitions have unit tests; `TestApp` covers rendering, filters, navigation, quit keys, resize, and atomic polling.

## Packaging note

This is a prototype and is not installed or shipped with `leader` yet. OpenTUI's native library bundles FFmpeg (LGPL-2.1-or-later) and other third-party components. A future packaged binary must include the license notices from the native archive and satisfy the corresponding distribution requirements.
