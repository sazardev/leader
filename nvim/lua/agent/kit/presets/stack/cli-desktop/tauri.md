<!-- name: Tauri 2 -->
<!-- desc: desktop app: Tauri 2, Rust core behind commands, Svelte or React front-end, capabilities, updater -->

# STACK.md: Tauri 2

## Summary

A cross-platform desktop app (Windows, macOS, Linux) built with Tauri 2: a Rust core that owns all privileged work
(filesystem, database, network, OS integration) and a web front-end rendered in the system webview. The only bridge
between them is a small set of typed **commands** and **events**; the front-end gets exactly the permissions its
capabilities grant, nothing more.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Shell | Tauri 2 | Small binaries, system webview, capability-based security |
| Core | Rust stable, `tokio` (Tauri's runtime), `thiserror`, `serde` | Safe, fast backend |
| Front-end | Svelte 5 + SvelteKit (static adapter) or React + Vite | SPA served from disk |
| Language (UI) | TypeScript `strict` | Typed calls to commands |
| Bindings | `tauri-specta` (or `ts-rs`) to generate TS types for commands | One contract, no drift |
| Storage | SQLite via `sqlx` (or `rusqlite`) in the Rust core | Local, transactional |
| Plugins | official `@tauri-apps/plugin-*` (fs, dialog, store, updater, log, shell) | Audited, permissioned |
| Styling | Tailwind CSS or CSS variables with design tokens | Consistent UI |
| Testing | `cargo test`, Vitest + Testing Library, WebdriverIO/`tauri-driver` e2e | Both sides covered |
| Lint/format | clippy + rustfmt; ESLint + Prettier (or Biome) | Strict |
| Release | `tauri-action` in GitHub Actions, code signing + notarization, updater with signed artifacts | Auto updates |

## Project layout

```
src/                                  front-end (Svelte/React)
  lib/api/commands.ts                 generated bindings (never edited) + thin wrappers
  lib/features/notes/                 components, stores, one per file
  lib/ui/                             design system components
  routes/ or App.tsx
src-tauri/
  Cargo.toml
  tauri.conf.json                     app config, bundle, updater endpoints
  capabilities/main.json              permissions granted to the main window
  src/
    main.rs                           calls app::run()
    lib.rs                            builder: plugins, state, invoke_handler, setup
    commands/
      notes.rs                        #[tauri::command] fns: validate input, call service, map errors
    services/notes_service.rs         business logic, no Tauri types
    domain/note.rs                    types
    db/                               sqlx pool, migrations, repositories
    error.rs                          serializable error enum returned to the UI
```

Dependency direction: `UI → commands (IPC) → services → domain`, `services → db` through traits. The UI never touches the filesystem or network directly except through granted plugins; services never import `tauri`.

## Conventions

- Commands are thin: deserialize args, call one service function, return `Result<T, AppError>` (serializable).
- One command group per file; commands registered in one `invoke_handler` list in `lib.rs`.
- Shared state via `tauri::State<T>` (`Mutex`/`RwLock` or pool), created in `setup`.
- Long work runs async; progress is pushed to the UI with events (`app.emit`), not polling.
- Every capability lists only the permissions needed, scoped (e.g. fs scope to `$APPDATA/**`).
- The UI calls commands only through the generated bindings in `lib/api`.
- New feature = domain type + service + command + capability/permission + regenerated bindings + UI feature folder.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm tauri dev` |
| Build | `pnpm tauri build` |
| Test core | `cargo test --manifest-path src-tauri/Cargo.toml` |
| Test UI | `pnpm test` |
| Lint | `cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings && pnpm lint` |
| Format | `cargo fmt --manifest-path src-tauri/Cargo.toml && pnpm format` |
| Add plugin | `pnpm tauri add <plugin>` |
| Icons | `pnpm tauri icon app-icon.png` |

## Testing

- Services and domain: Rust unit tests with in-memory SQLite and trait fakes.
- Commands: tests calling the functions directly with a mock state (no window needed); `tauri::test` for IPC-level checks.
- UI: component tests with Vitest, command bindings mocked (`@tauri-apps/api/mocks` `mockIPC`).
- e2e: WebdriverIO with `tauri-driver` for critical flows on Linux/Windows CI.

## Quality gates

- clippy `-D warnings`, rustfmt, ESLint, Prettier and `tsc --noEmit` clean.
- All tests pass; bindings regenerated with no diff.
- Capabilities reviewed in every PR that changes them; no wildcard permissions.
- Release builds are signed; updater artifacts signed with the private key kept in CI secrets.

## Dependencies

- Official Tauri plugins first; community plugins only after reviewing their permissions.
- Do NOT use: Electron-style Node APIs in the UI, `shell:allow-execute` with unrestricted scopes, `dangerousRemoteDomainIpcAccess`-style remote IPC, storing secrets in the front-end or `localStorage`, `unwrap()` in command handlers.

## Rules for agents

- Put privileged logic in Rust services, never in the front-end.
- Every new command: input validation, typed error, registration, capability permission, regenerated TS bindings, test.
- Never widen a capability scope without saying why in the change.
- Never edit generated bindings; regenerate them.
- Commands must not block: use async commands or spawn blocking work with `tauri::async_runtime::spawn_blocking`.
- Never return raw `String` errors; use the serializable `AppError`.
- Keep `lib.rs` as the only place where plugins and state are wired.
- UI calls go through `lib/api`; no `invoke("...")` with string names scattered in components.
