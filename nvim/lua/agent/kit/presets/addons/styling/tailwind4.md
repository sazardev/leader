<!-- name: Tailwind CSS 4 -->
<!-- desc: CSS-first config with @theme tokens, Vite plugin, no tailwind.config.js -->
<!-- for: ui -->
<!-- default: web fullstack !lit -->

## Stack

| Styling | Tailwind CSS 4 (`@tailwindcss/vite`), tokens in `@theme` in the main CSS file | Utilities generated from your tokens; no config file, fast builds |

## Project layout

```
src/styles/app.css             @import "tailwindcss"; @theme { --color-*, --font-*, --spacing … } (the design tokens)
```

## Conventions

- Design tokens live in `@theme` (colors, fonts, radius, spacing) and mirror DESIGN.md; components use the generated utilities (`bg-primary`, `text-muted`).
- Long class lists are composed in one place (a variant helper such as `cva` or a component), not repeated across files.
- Arbitrary values (`w-[317px]`) only with a comment; a repeated one becomes a token.

## Rules for agents

- Never hardcode a color, font size or radius in a class or style: use a token from `@theme`, or add it there first.
- Never add a second CSS framework or a CSS-in-JS runtime.
- Do not write `@apply` chains to rebuild components in CSS: make a component.
