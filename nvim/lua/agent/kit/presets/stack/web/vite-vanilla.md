<!-- name: Vite + TypeScript (no framework) -->
<!-- desc: performance first: Vite 8 + TypeScript 7, plain ES modules, Web Components only where needed, tiny bundles -->

# STACK.md: Vite + TypeScript (no framework)

## Summary

A web front end with no UI framework: plain TypeScript modules, the DOM and the platform (Web Components, `fetch`,
`URL`, `<dialog>`, CSS custom properties). Vite 8 serves it in development and bundles it with Rolldown. Chosen when
performance and longevity matter more than a component ecosystem: the shipped JavaScript is only your code. Logic is
kept out of the DOM: pure modules hold state and rules, thin view modules render and bind events.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (native `tsc`, `strict`, `noUncheckedIndexedAccess`, `verbatimModuleSyntax`) | Types with near-instant checks |
| Build | Vite 8 (Rolldown bundler) | Fast dev server, Rust bundler, code splitting by `import()` |
| UI | DOM APIs + native Web Components (`customElements`) where reuse needs encapsulation | Zero runtime, platform-stable |
| State | Small typed stores (`EventTarget` + a `subscribe` function) | Explicit, no library |
| Routing | `URLPattern` / History API in one `router.ts` (or multi-page Vite build) | No router dependency |
| Styling | Plain CSS with custom properties and cascade layers; CSS modules per component | No runtime CSS |
| Validation | Valibot (tree-shakable) at the API boundary | ~1 KB for what you use |
| Testing | Vitest (happy-dom) + Playwright | Unit for logic, browser for flows |
| Lint/format | ESLint (`typescript-eslint` strict) + Prettier | One style |
| Package manager | pnpm | Fast, strict `node_modules` |
| Deploy | Static files on any CDN | Nothing to run |

## Project layout

```
index.html                       entry: critical CSS inline, one module script
src/
  main.ts                        bootstraps: router, stores, registers components
  router.ts                      URL → page module (dynamic import per page)
  core/
    store.ts                     tiny typed store (EventTarget based)
    http.ts                      fetch wrapper: base URL, timeouts (AbortSignal.timeout), typed errors
    dom.ts                       helpers: html escape, `qs`, event delegation
  features/
    cart/
      cart.model.ts              pure state + rules (no DOM)
      cart.store.ts              store instance + actions
      cart.view.ts               renders into a root element, binds events
      cart-badge.element.ts      Web Component (only when reused across pages)
      cart.model.test.ts
  styles/
    tokens.css                   custom properties (colors, spacing, type)
    base.css                     reset + layers
public/                          static assets copied as is
e2e/                             Playwright specs
```

Dependency direction: `view → store → model`; `model` imports nothing from the DOM or `http`. Features never import each
other's views; shared pieces move to `core/`.

## Conventions

- One module = one responsibility: `*.model.ts` (pure), `*.store.ts` (state), `*.view.ts` (DOM), `*.element.ts` (custom element).
- Never build HTML from untrusted strings: use `textContent` or the escaping helper; `innerHTML` only with static templates.
- Pages are loaded with `import()` so each route is its own chunk; nothing heavy in `main.ts`.
- Events are delegated from a feature's root element; listeners are removed when a view unmounts (`AbortController` signal).
- Errors from `http.ts` are typed (`HttpError`, `NetworkError`) and rendered by the view as a retry state.
- Files over ~200 lines are split; no `utils.ts` dumping ground.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm dev` (`vite`) |
| Build | `pnpm build` (`tsc --noEmit && vite build`) |
| Preview build | `pnpm preview` |
| Typecheck | `pnpm typecheck` (`tsc --noEmit`) |
| Test | `pnpm test` (`vitest run`) |
| E2E | `pnpm test:e2e` (`playwright test`) |
| Lint | `pnpm lint` |
| Bundle report | `pnpm build --mode analyze` (`rollup-plugin-visualizer` or `vite-bundle-analyzer`) |

## Testing

- Models and stores: Vitest unit tests, no DOM.
- Views and elements: Vitest with happy-dom, asserting rendered text and events, not markup snapshots.
- Flows: Playwright against `vite preview` (the real build), on Chromium and WebKit.
- A bug fix starts with a failing test.

## Quality gates

- `tsc --noEmit` clean, ESLint zero warnings, Prettier check.
- Performance budgets in CI (Lighthouse CI or `size-limit`): initial JS ≤ 30 KB gzip, CSS ≤ 20 KB gzip, LCP ≤ 2.0 s and INP ≤ 200 ms on a mid-range mobile profile, CLS ≤ 0.1.
- Playwright smoke suite green on the production build.

## Dependencies

- The platform first: DOM, `fetch`, `URL`, `Intl`, `<dialog>`, `popover`, View Transitions.
- A runtime dependency must be tree-shakable, ESM, and justify its gzip size in the PR.
- Do NOT use: jQuery, Lodash (use native methods), Moment.js (use `Intl`/`Temporal` polyfill only if needed), a UI framework added "for one widget", CSS-in-JS runtimes.

## Rules for agents

- Never add a UI framework or a state library; solve it with modules, stores and Web Components.
- Never put DOM access in `*.model.ts`; keep rules testable without a browser.
- Never use `innerHTML` with data; escape or use `textContent`.
- Every new page is a dynamic `import()` from `router.ts`.
- Every listener is tied to an `AbortController` signal so it is removed on unmount.
- Check the bundle report when adding a dependency; stay inside the budgets.
- Images get `width`/`height`, `loading="lazy"` below the fold and modern formats (AVIF/WebP).
- Colors, spacing and type come from `tokens.css` custom properties, never literals.
