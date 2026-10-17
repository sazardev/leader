<!-- name: CSS variables -->
<!-- desc: the design in plain CSS: tokens as custom properties on :root, a data-theme switch, one file per layer -->
<!-- for: gui -->
<!-- default: !tailwind !flutter ui -->

## Toolkit

| Design | CSS |
| --- | --- |
| Color token | a custom property on `:root` (`--color-surface`, `--color-text-muted`…); dark values on `[data-theme=dark]` |
| Type scale | `--font-size-<step>` with `clamp()` where the design is fluid; `--font-<family>` |
| Spacing | `--space-<step>` on a 4 px base; components use only these |
| Radius / shadow | `--radius-<name>`, `--shadow-<name>` |
| Layout | grid and flex; `max-width` containers; container queries for components that change with their slot |
| Motion | `--duration-<name>`, `--ease-<name>`; everything under `@media (prefers-reduced-motion: no-preference)` |
| Layers | `@layer reset, tokens, base, components, utilities;` so order never depends on import order |

- `tokens.css` holds every custom property; no other file declares a raw color, size or duration.

## Rules for agents

- A component reads tokens (`var(--color-accent)`); a new value goes into `tokens.css` first.
- Class names follow one scheme (BEM or one class per component); no IDs for styling.
