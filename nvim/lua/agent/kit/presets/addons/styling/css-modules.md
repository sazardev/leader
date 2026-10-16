<!-- name: CSS Modules + tokens -->
<!-- desc: scoped CSS Modules, design tokens as CSS custom properties, zero runtime -->
<!-- for: ui -->

## Stack

| Styling | CSS Modules (`*.module.css`) + design tokens as CSS custom properties in `tokens.css` | Scoped by default, plain CSS, no runtime and no build plugin |

## Project layout

```
src/styles/tokens.css          :root and [data-theme="dark"] custom properties (colors, spacing, radius, fonts)
src/styles/global.css          reset, base element styles; imports tokens.css
src/components/Button/Button.module.css   one module per component, next to it
```

## Conventions

- Every value with a token is read through `var(--token)`; tokens mirror DESIGN.md.
- One `.module.css` per component, next to the component, with class names describing the role (`.root`, `.label`, `.isActive`).
- Dark mode by swapping custom properties under `[data-theme="dark"]` (and `prefers-color-scheme`), never by duplicating rules.

## Rules for agents

- Never hardcode a color, size or radius: use `var(--…)` or add the token to `tokens.css` first.
- Never style another component's internals from outside: pass a `className` or a variant prop.
- No global class names except in `global.css`.
