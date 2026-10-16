<!-- name: Alpine.js (+ htmx) -->
<!-- desc: minimal JS on server-rendered or static HTML: Alpine.js sprinkles, optional htmx, Vite 8 for assets -->

# STACK.md: Alpine.js (+ htmx)

## Summary

HTML comes from the server (any backend: Go, Django, Laravel, Rails) or from static files; interactivity is added with
Alpine.js directives for local UI state (menus, tabs, modals, form helpers) and, when parts of the page must change from
the server, htmx swaps HTML fragments. Vite 8 only bundles the small JS and CSS entry. The page works without JavaScript
for its core content; JavaScript enhances it.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 for the few modules (native `tsc`), plain HTML for markup | Typed components where logic exists |
| Interactivity | Alpine.js 3 (`Alpine.data` components) | ~15 KB gzip, declarative, no build needed for markup |
| Server swaps | htmx 2 (optional) | Hypermedia: the server stays the source of truth |
| Build | Vite 8 (Rolldown) with a manifest for the backend | Hashed assets, dev server with HMR for CSS/JS |
| Styling | Tailwind CSS 4 (or plain CSS with custom properties) | Utility classes in templates |
| Testing | Vitest (Alpine components as plain objects) + Playwright | Logic and real flows |
| Lint/format | ESLint + Prettier (+ `prettier-plugin-tailwindcss`) | |
| Package manager | pnpm | |
| Deploy | Served by the backend or a CDN | |

## Project layout

```
assets/
  main.ts                        imports Alpine + plugins, registers components, Alpine.start()
  alpine/
    dropdown.ts                  Alpine.data('dropdown', () => ({ open: false, toggle() {…} }))
    tabs.ts
    form-validate.ts             client hints; the server always validates
    stores/cart.ts               Alpine.store('cart', …) for state shared across components
  htmx/
    config.ts                    htmx.config, events (htmx:afterSwap → re-init), CSRF header
  styles/main.css
templates/ (or the backend's views)  HTML using x-data="dropdown", hx-get, hx-target
vite.config.ts                   build.manifest: true, input: assets/main.ts
e2e/
```

Dependency direction: templates → Alpine components → stores. Components never call each other directly; they share
through stores or DOM events (`$dispatch`).

## Conventions

- Inline `x-data` only for one-liners; anything with logic is a named `Alpine.data` component in its own file.
- Business rules and validation live on the server; Alpine only improves the experience.
- htmx requests return HTML fragments; Alpine state inside swapped content is re-initialised by Alpine automatically.
- Use `x-cloak` with a CSS rule to avoid flashes; prefer `x-show` for toggles and `x-if` for heavy, rarely shown blocks.
- Every form works as a normal POST without JavaScript.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm dev` (Vite) + the backend's dev server |
| Build | `pnpm build` (manifest read by the backend) |
| Typecheck | `pnpm typecheck` |
| Test | `pnpm test` |
| E2E | `pnpm test:e2e` |
| Lint | `pnpm lint` |

## Testing

- Alpine components are factories returning plain objects: unit test them with Vitest without a DOM.
- Flows (menus, forms, htmx swaps) with Playwright against the running backend.
- The core content is also checked with JavaScript disabled.

## Quality gates

- Typecheck, lint and format clean.
- Budgets: total JS ≤ 40 KB gzip (Alpine + htmx + your code), LCP ≤ 1.8 s, INP ≤ 200 ms, CLS ≤ 0.1.
- Pages render and are usable without JavaScript (Playwright with JS off).

## Dependencies

- Alpine official plugins (`@alpinejs/focus`, `collapse`, `persist`) before third-party ones.
- Do NOT use: jQuery, a SPA framework for parts of the page, client-side routing, duplicating server validation as the only validation.

## Rules for agents

- Never move business logic or authorization into Alpine; the server decides.
- Named `Alpine.data` components for anything beyond one expression.
- Every form must work without JavaScript; Alpine/htmx only enhance it.
- htmx responses are fragments with correct status codes (422 for validation errors).
- Every interactive widget is keyboard accessible (`@alpinejs/focus` for traps in dialogs).
- Use `$dispatch`/stores for cross-component communication, never global variables.
- Stay inside the JS budget; check the build manifest sizes when adding a plugin.
- Escape data in templates on the server; never inject HTML with `x-html` from user input.
