<!-- name: Go + Wails desktop -->
<!-- desc: Desktop apps with a Go core and a web front-end (Vite + TS): Wails bindings, native menus, one binary -->

# STACK.md: Go + Wails desktop

## Summary

A desktop application for Windows, macOS and Linux with a Go backend and a web front-end rendered in the OS webview. Wails
generates TypeScript bindings for exported Go methods, so the UI calls Go like typed async functions; events flow back for
progress and notifications. The Go core is plain, testable Go; the Wails layer only exposes it.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Go 1.25+ (backend) + TypeScript (front-end) | Fast native core, web UI |
| Shell | Wails v2 (stable; v3 when it is final in your environment) | Native webview, small binaries |
| Front-end | Vite + TypeScript (Svelte, React or vanilla) | Fast dev, typed bindings |
| Storage | SQLite (`modernc.org/sqlite`) in the user config dir | No server, no CGO |
| Logging | `log/slog` to a file in the app data dir | Debuggable in the field |
| Testing | Go `testing` for the core; Vitest for the front-end | Each side tested natively |
| Lint | golangci-lint v2; Biome on the front-end | Strict |
| Package | `wails build` (+ NSIS on Windows, signed .app on macOS) | Installers per OS |

## Project layout

```
main.go                     wails.Run: window options, bind App
app.go                      App struct: exported methods = the front-end's API (thin)
internal/
  notes/
    note.go                 domain
    service.go              use cases
    store.go                port
    store_sqlite.go         adapter
    service_test.go
  platform/
    paths.go                config/data dirs per OS
frontend/
  src/
    main.ts
    features/notes/notes-view.ts
    lib/api.ts              re-exports wailsjs bindings with app types
  wailsjs/                  generated bindings (never edited)
wails.json
```

Dependency direction: `frontend → wailsjs bindings → app.go → internal/*`; `internal` never imports Wails.

## Conventions

- `app.go` methods are thin: convert inputs, call a service, return plain structs or errors.
- Long work runs in goroutines and reports progress with `runtime.EventsEmit`; the UI never blocks on it.
- File dialogs and menus through Wails runtime calls in `app.go` only.

## Commands

| Task | Command |
| --- | --- |
| Dev | `wails dev` |
| Build | `wails build -clean` |
| Test (Go) | `go test ./...` |
| Test (UI) | `cd frontend && pnpm vitest run` |
| Lint | `golangci-lint run && (cd frontend && pnpm biome check .)` |
| Bindings | `wails generate module` |

## Testing

- Services and stores tested in Go with a temp SQLite file; front-end logic with Vitest and mocked bindings.

## Quality gates

- golangci-lint, `go test -race ./...`, Biome and Vitest clean; `wails build` succeeds on each target OS in CI.

## Dependencies

- Wails, modernc SQLite, standard library first.
- Do NOT use: CGO-only libraries (they break cross-builds), a local HTTP server instead of bindings, editing `wailsjs/`.

## Rules for agents

- Keep business logic out of `app.go`; it only adapts calls.
- Never edit generated bindings; regenerate them.
- Store data under the OS user data dir, never next to the binary.
- Emit events for progress; never block the UI thread with long calls.
- Return errors from bound methods; the front-end shows them, it does not crash.
- Keep the front-end free of Node APIs: it runs in a webview.
- Test the Go core without Wails.
- Sign and notarize release builds before shipping.
