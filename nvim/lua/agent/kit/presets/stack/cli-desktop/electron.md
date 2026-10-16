<!-- name: Electron + Vite -->
<!-- desc: Electron desktop app in TypeScript: main/preload/renderer split, contextIsolation, typed IPC, electron-builder -->

# STACK.md: Electron + Vite

## Summary

A cross-platform desktop application on Electron with TypeScript everywhere. Three processes with hard boundaries: the
**main** process owns windows, files and OS access; a **preload** script exposes a small typed API through
`contextBridge`; the **renderer** is a sandboxed web app built with Vite. Security defaults are on: `contextIsolation`,
`sandbox`, no `nodeIntegration`, strict CSP.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (strict) | One typed language for all three processes |
| Shell | Electron (current stable) | Chromium + Node, mature |
| Build | electron-vite (Vite 8 for main, preload and renderer) | One config, fast HMR |
| UI | React 19 or Svelte 5 in the renderer | Any web UI |
| IPC | Typed channels declared once, `ipcRenderer.invoke` / `ipcMain.handle` | No stringly-typed messages |
| Storage | `better-sqlite3` or JSON files in `app.getPath("userData")` | Local data |
| Testing | Vitest (main/renderer logic) + Playwright for Electron | Unit and app-level |
| Lint | Biome | One tool |
| Package manager | pnpm | Strict, fast |
| Package | electron-builder (signing, auto-update) | Installers and updates |

## Project layout

```
src/
  main/
    index.ts                 app lifecycle, BrowserWindow (secure options)
    ipc/notes.ipc.ts         ipcMain.handle for one feature
    services/notes.service.ts
    services/notes.store.ts
  preload/
    index.ts                 contextBridge.exposeInMainWorld("api", typed api)
  shared/
    ipc-contract.ts          channel names + request/response types (imported by all three)
  renderer/
    index.html
    src/main.tsx
    src/features/notes/notes-page.tsx
    src/lib/api.ts           window.api typed
electron.vite.config.ts
electron-builder.yml
```

Dependency direction: `renderer → preload API → main ipc → services`; the renderer never imports Node or Electron modules.

## Conventions

- Every IPC channel is declared in `shared/ipc-contract.ts` with its types; preload exposes functions, not `ipcRenderer`.
- `BrowserWindow` with `contextIsolation: true`, `sandbox: true`, `nodeIntegration: false`; CSP meta in `index.html`.
- Main validates every IPC input (it comes from a web page).

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm electron-vite dev` |
| Typecheck | `pnpm tsc --noEmit` |
| Test | `pnpm vitest run` |
| Build | `pnpm electron-vite build` |
| Package | `pnpm electron-builder` |

## Testing

- Services in main tested with Vitest; renderer components with Testing Library; Playwright `_electron.launch` for the main flows.

## Quality gates

- Typecheck, Biome, Vitest and Playwright green; packaged app starts on each target OS in CI; Electron security checklist reviewed.

## Dependencies

- Electron, electron-vite, electron-builder, one UI library.
- Do NOT use: `nodeIntegration: true`, `remote` module, exposing `ipcRenderer` itself to the renderer, loading remote code.

## Rules for agents

- Never enable `nodeIntegration` or disable `contextIsolation`/`sandbox`.
- Add a channel to `ipc-contract.ts` before using it anywhere.
- Validate IPC arguments in main; treat the renderer as untrusted.
- Keep file system and OS calls in main services only.
- Store user data under `app.getPath("userData")`.
- Keep the preload API minimal: functions with typed arguments, nothing generic.
- Open external links with `shell.openExternal` after validating the URL.
- Sign builds and enable auto-update only over HTTPS.
