<!-- name: Browser extension (WXT + TypeScript) -->
<!-- desc: cross-browser MV3 extension with WXT: background, content scripts, popup, typed messaging, minimal permissions -->

# STACK.md: Browser extension (WXT + TypeScript)

## Summary

A Manifest V3 browser extension for Chrome and Firefox built with WXT (Vite-based). Entrypoints are files: a background
service worker, content scripts, a popup and an options page. They communicate through typed messages; storage is typed
and versioned; permissions are the minimum the features need. Logic that does not need browser APIs is plain TypeScript
tested with Vitest.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (native `tsc`, strict) | Typed messages and storage |
| Framework | WXT 0.20 | File-based entrypoints, MV3 for Chrome and Firefox, HMR |
| UI | Vanilla TS or Preact for popup/options (small bundles) | Extensions should load instantly |
| Messaging | `@webext-core/messaging` (typed protocol) | One typed map of messages |
| Storage | WXT `storage` with defined items and versions | Migrations between versions |
| Testing | Vitest + WXT testing utils (fake browser) | |
| E2E | Playwright with the unpacked extension (Chromium) | |
| Package manager | pnpm | |
| Lint/format | ESLint (typescript-eslint) + Prettier | |

## Project layout

```
wxt.config.ts                   manifest fields, permissions, host_permissions
entrypoints/
  background.ts                 service worker: registers message handlers, alarms; no DOM
  content/
    index.ts                    content script: matches, mounts UI; thin
    overlay.ts                  DOM pieces it injects
  popup/
    index.html
    main.ts
  options/
    index.html
    main.ts
lib/
  messages.ts                   the typed protocol: message name → payload → response
  storage.ts                    storage items with defaults and versions/migrations
  features/
    summarize/
      summarize.ts              pure logic (testable)
      summarize.handler.ts      background handler for its message
  dom/                          helpers used by content scripts only
public/icons/
tests/
  features/summarize.test.ts
  e2e/popup.spec.ts
```

Dependency direction: `entrypoints → lib/features → lib/{messages,storage}`; feature logic never imports browser APIs
directly (handlers do).

## Conventions

- Every message is declared once in `lib/messages.ts`; senders and handlers are typed from it.
- The background worker is stateless between wake-ups: state lives in `storage`, not module variables (MV3 kills it).
- Content scripts stay thin: read the page, send a message, render; heavy work runs in the background.
- Permissions: only what a feature needs; `optional_permissions` + runtime request for rarely used ones; host
  permissions as narrow as possible.
- Storage items have defaults and a version; changes add a migration.
- No remote code: everything is bundled (MV3 forbids remotely hosted code).

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev (Chrome) | `pnpm dev` |
| Dev (Firefox) | `pnpm dev:firefox` |
| Build | `pnpm build` (and `pnpm build:firefox`) |
| Zip for stores | `pnpm zip` |
| Typecheck | `pnpm exec tsc --noEmit` |
| Test | `pnpm test` |

## Testing

- Vitest for feature logic, message handlers (with WXT's fake browser) and storage migrations.
- Playwright: load the built extension in Chromium, open the popup, run the main flow on a fixture page.
- Manual check in Firefox before publishing.

## Quality gates

- Typecheck, lint, tests green; `pnpm build` for both browsers succeeds.
- Manifest review: no new permission without a line in the PR saying which feature needs it.

## Dependencies

- Allowed: WXT, the table above. UI libraries only if they keep the popup bundle small.
- Do NOT use: remotely hosted scripts, `eval`/`new Function`, `<all_urls>` without a reason, module-level state in the
  background worker, untyped `chrome.runtime.sendMessage` calls.

## Rules for agents

- Declare every message in `lib/messages.ts` and use the typed helpers to send and handle it.
- Keep background state in storage; assume the service worker can stop at any time.
- Keep content scripts thin; move processing to background handlers or pure feature modules.
- Never add a permission or host permission without stating which feature needs it.
- Add a storage migration when a stored shape changes.
- Never load or evaluate remote code.
- Put feature logic in `lib/features/<name>/` with a Vitest test.
- Build for Chrome and Firefox before finishing.
- Sanitize anything inserted into pages; never use `innerHTML` with page or remote data.
