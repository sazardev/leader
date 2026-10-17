<!-- name: Tailwind CSS -->
<!-- desc: the design in Tailwind v4 terms: tokens in @theme, utilities only, dark variant, components as markup patterns -->
<!-- for: gui -->
<!-- default: tailwind -->

## Toolkit

| Design | Tailwind CSS v4 |
| --- | --- |
| Color token | a `--color-<token>` variable in the `@theme` block of the main CSS file (`bg-surface`, `text-muted` then exist) |
| Type scale | `--text-<step>` (+ `--text-<step>--line-height`) and `--font-<family>` in `@theme` |
| Spacing | `--spacing` is the base unit; use the scale (`p-4`, `gap-6`), never arbitrary `p-[13px]` |
| Radius / shadow | `--radius-<name>`, `--shadow-<name>` in `@theme` |
| Dark mode | `@custom-variant dark` on `[data-theme=dark]` (or the media query); dark values override the same variables |
| Layout | flex and grid utilities; containers `max-w-*` + `mx-auto`; breakpoints `sm md lg xl` mobile first |
| Motion | `--animate-<name>` + `@keyframes` in `@theme`; `motion-safe:` / `motion-reduce:` variants |
| Components | a component = one markup pattern with its utilities in one place (a framework component, or `@utility` for a repeated piece) |

- Every value the design names exists as a theme variable; a class never carries a raw hex or pixel value.
- Long class lists are ordered by the official Prettier plugin (`prettier-plugin-tailwindcss`).

## Rules for agents

- New colors, sizes or radii go into `@theme` first, then are used as utilities.
- No `@apply` chains to rebuild a CSS framework; components are markup.
