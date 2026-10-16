<!-- name: Lit web components -->
<!-- desc: framework-agnostic component library / design system: Lit 3, TypeScript 7, Vite 8, @open-wc testing -->

# STACK.md: Lit web components

## Summary

A component library (or design system) built as standard Web Components with Lit: reactive properties, efficient
template updates and Shadow DOM styles, usable from any framework or plain HTML. Published as ESM to npm, with tokens as
CSS custom properties so consumers theme it. Each component is its own module and can be imported alone.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (native `tsc`, `strict`, `experimentalDecorators` off: standard decorators) | Typed properties and events |
| Components | Lit 3 | ~5 KB, standards-based, works everywhere |
| Build | Vite 8 library mode (Rolldown) + `tsc` for `.d.ts` | ESM output, one entry per component |
| Tokens | CSS custom properties generated from a tokens file (Style Dictionary) | Themeable across frameworks |
| Docs / playground | Storybook (web-components-vite) — optional | Visual catalogue |
| Manifest | Custom Elements Manifest (`@custom-elements-manifest/analyzer`) | IDE and framework wrappers |
| Testing | `@web/test-runner` + `@open-wc/testing` (real browsers) + Playwright | Components tested in real DOM |
| Accessibility | `@open-wc/testing` a11y assertions (axe) | Checked per component |
| Lint/format | ESLint (`eslint-plugin-lit`, `eslint-plugin-wc`) + Prettier | |
| Releases | Changesets | Versioned, changelog |
| Package manager | pnpm | |

## Project layout

```
src/
  index.ts                       re-exports every component (side-effect free)
  tokens/
    tokens.json                  source of design tokens
    tokens.css                   generated custom properties (never edited)
  components/
    button/
      button.ts                  class MyButton extends LitElement (one element per file)
      button.styles.ts           css`` styles using tokens
      button.test.ts
      button.stories.ts          optional
      define.ts                  customElements.define('my-button', MyButton) guarded
  internal/
    focus.ts                     shared controllers (ReactiveController), not exported
custom-elements.json             generated manifest
```

Dependency direction: `components → internal → tokens`. Components never import each other's internals; composition is
through slots and public properties.

## Conventions

- One element per file; class and tag names match (`MyButton` ↔ `my-button`); every tag has a prefix.
- Public API = properties (reflected only when needed for styling), slots, CSS parts and custom events (`my-change`, `bubbles: true, composed: true`). Document all of them with JSDoc for the manifest.
- Defining is separate from the class (`define.ts`) so consumers can register with their own names.
- Styles only from tokens; expose `::part` and custom properties for customization, never require piercing Shadow DOM.
- Form controls use `ElementInternals` (`static formAssociated = true`).

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm dev` (Storybook or Vite playground) |
| Build | `pnpm build` (tokens → `vite build` → `tsc --emitDeclarationOnly` → manifest) |
| Typecheck | `pnpm typecheck` |
| Test | `pnpm test` (`web-test-runner`, Chromium/Firefox/WebKit) |
| Lint | `pnpm lint` |
| Release | `pnpm changeset` then `pnpm release` |

## Testing

- Each component: render with `fixture()`, assert properties, events, keyboard behaviour and `isAccessible()`.
- Cross-browser runs in Chromium, Firefox and WebKit.
- Visual regressions on stories (optional, Playwright screenshots).

## Quality gates

- Typecheck, lint and tests in three browsers green; no axe violations.
- Budgets: each component ≤ 3 KB gzip on top of Lit; the full library ≤ 40 KB gzip.
- The Custom Elements Manifest is regenerated and committed; a public API change needs a changeset.

## Dependencies

- Lit and its official packages (`@lit/context`, `@lit/task`) first.
- Do NOT use: framework-specific code inside components, global CSS that must be loaded for components to work, Shadow-DOM-piercing styles, heavy runtime dependencies.

## Rules for agents

- Never break the public API (tag, properties, events, slots, parts) without a major changeset.
- Every component is keyboard operable and passes the axe assertion in its test.
- No hardcoded colors or sizes: use tokens via custom properties.
- Events are `CustomEvent`s with typed `detail`, `bubbles` and `composed` set deliberately.
- Never call `customElements.define` at import of the class module; use `define.ts`.
- New components get a test file and, if Storybook is used, a story.
- Keep render pure: no side effects in `render()`; use lifecycle hooks or controllers.
- Regenerate `tokens.css` and the manifest instead of editing them.
