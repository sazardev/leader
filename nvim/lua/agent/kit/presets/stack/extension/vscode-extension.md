<!-- name: VS Code extension (TypeScript) -->
<!-- desc: VS Code extension in TypeScript: lazy activation, commands per file, contributes, esbuild, test-electron -->

# STACK.md: VS Code extension (TypeScript)

## Summary

A Visual Studio Code extension written in TypeScript and bundled with esbuild. It activates lazily on the events that
need it, every command lives in its own file, everything it adds to the editor is declared in `package.json`
`contributes`, and every resource it creates is disposed. Logic that does not need the `vscode` API is plain TypeScript
tested with Vitest; the integration is tested inside VS Code with `@vscode/test-electron`.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (native `tsc`, strict) | Typed `vscode` API |
| Runtime | VS Code extension host (Node), `engines.vscode` pinned | |
| Bundler | esbuild (single `dist/extension.js`) | Fast activation, small package |
| Unit tests | Vitest (pure logic, no `vscode`) | Fast |
| Integration tests | `@vscode/test-electron` + `@vscode/test-cli` (Mocha) | Real editor |
| Packaging | `@vscode/vsce` (`.vsix`), Open VSX with `ovsx` | |
| Package manager | pnpm | |
| Lint/format | ESLint (typescript-eslint) + Prettier | |

## Project layout

```
package.json                    activationEvents, contributes (commands, configuration, menus, views)
src/
  extension.ts                  activate(): registers commands/providers, pushes disposables; deactivate()
  commands/
    format-selection.ts         one command per file: exports its id and a handler
    open-panel.ts
  providers/
    hover-provider.ts           language features, one provider per file
  config.ts                     typed access to contributes.configuration settings
  services/
    analyzer.ts                 pure logic (no vscode import) — unit tested
  webviews/
    panel.ts                    webview with CSP, nonce, message protocol
    messages.ts
test/
  unit/analyzer.test.ts         Vitest
  suite/extension.test.ts       runs inside VS Code
esbuild.mjs
```

Dependency direction: `extension.ts → commands/providers → services`; `services/` never imports `vscode`.

## Conventions

- Activate lazily: `activationEvents` (or implicit command/language activation), never `*`.
- Every command is declared in `contributes.commands`, implemented in its own file and registered in `activate`.
- Every disposable goes into `context.subscriptions`.
- Settings declared in `contributes.configuration` and read through `config.ts`, reacting to `onDidChangeConfiguration`.
- Webviews: strict Content Security Policy with a nonce, `localResourceRoots` limited, typed message protocol.
- Long work is async and cancellable (`CancellationToken`, progress notifications); never block the extension host.
- Output through a dedicated `OutputChannel`, not `console.log`.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Build | `pnpm build` (esbuild) |
| Watch | `pnpm watch` |
| Typecheck | `pnpm exec tsc --noEmit` |
| Unit tests | `pnpm vitest run` |
| Integration tests | `pnpm exec vscode-test` |
| Package | `pnpm exec vsce package --no-dependencies` |

## Testing

- Vitest for `services/` and any pure helpers.
- Integration tests (test-electron) for command registration, a provider on a fixture workspace and configuration changes.
- Manual run with F5 (Extension Development Host) for UX before releases.

## Quality gates

- Typecheck, lint, unit and integration tests green; `vsce package` succeeds with no warnings.
- Activation time checked (Developer: Show Running Extensions) after adding activation events.

## Dependencies

- Allowed: the table above; runtime dependencies bundled by esbuild and justified.
- Do NOT use: `*` activation, synchronous file IO on the extension host, webviews without CSP, `console.log` for user
  output, private/proposed APIs in a published extension.

## Rules for agents

- Put each command in `src/commands/<name>.ts`, declare it in `contributes.commands` and register it in `activate`.
- Push every disposable to `context.subscriptions`.
- Keep `vscode` imports out of `services/`; test services with Vitest.
- Read settings only through `config.ts` and handle configuration changes.
- Use specific activation events; never `*`.
- Give webviews a CSP with a nonce and a typed message protocol.
- Make long operations async, cancellable and reported with progress.
- Write user-facing logs to the extension's OutputChannel.
- Run the integration tests after changing activation, commands or providers.
