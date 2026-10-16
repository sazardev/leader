<!-- name: Vercel Geist -->
<!-- desc: Vercel's Geist: Geist Sans and Mono, 10-step gray and color scales, high-contrast developer UI -->

# DESIGN.md: Vercel Geist

Geist, the design system of Vercel. Source of truth: vercel.com/geist. Colors are 10-step scales (100–1000) per hue with
light and dark themes; typography is Geist Sans and Geist Mono. Many exact values below are approximations of the public
site and are marked so.

## Principles

- **High contrast, low noise**: near-black and near-white with grays; color only for status and focus.
- **Developer clarity**: code, logs and numbers are first-class (Geist Mono, tabular figures).
- **Precision**: crisp 1px borders, consistent radius, aligned grids.
- **Speed**: fast, subtle motion; nothing waits on an animation.

## Color

Scales: `gray`, `gray-alpha`, `blue`, `red`, `amber`, `green`, `teal`, `purple`, `pink`, each 100 (background) → 1000 (text).
Steps 100–300 component backgrounds, 400–600 borders, 700–800 solids, 900–1000 text.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `--ds-background-100` | `#FFFFFF` | `#0A0A0A` (approx.) | App background |
| `--ds-background-200` | `#FAFAFA` | `#000000` (approx.) | Secondary background |
| `--ds-gray-100` | `#F2F2F2` (approx.) | `#1A1A1A` (approx.) | Component background |
| `--ds-gray-400` | `#EBEBEB` (approx.) | `#2E2E2E` (approx.) | Borders |
| `--ds-gray-900` | `#666666` (approx.) | `#A1A1A1` (approx.) | Secondary text |
| `--ds-gray-1000` | `#171717` | `#EDEDED` | Primary text |
| `--ds-blue-700` | `#0070F3` (approx.) | `#0070F3` (approx.) | Links, focus, primary accent |
| `--ds-red-800` | `#E5484D` (approx.) | `#E5484D` (approx.) | Errors |
| `--ds-amber-800` | `#FFB224` (approx.) | `#FFB224` (approx.) | Warnings |
| `--ds-green-800` | `#45A557` (approx.) | `#45A557` (approx.) | Success |

- Primary buttons are `gray-1000` background with `background-100` text (black on light, white on dark).

## Typography

Fonts: Geist Sans (UI) and Geist Mono (code, numbers); `geist` npm package or `next/font`.

| Class | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| `text-heading-72` | 72 / 72 | 600 | Hero (approx.) |
| `text-heading-48` | 48 / 56 | 600 | Page hero |
| `text-heading-32` | 32 / 40 | 600 | Page title |
| `text-heading-24` | 24 / 32 | 600 | Section |
| `text-heading-20` | 20 / 26 | 600 | Card title |
| `text-heading-16` | 16 / 24 | 600 | Small heading |
| `text-copy-16` | 16 / 24 | 400 | Long text |
| `text-copy-14` | 14 / 20 | 400 | Default UI text |
| `text-label-13` | 13 / 16 | 400–500 | Labels |
| `text-label-12-mono` | 12 / 16 | 400 | Metadata, IDs |

Headings use slight negative tracking (approx. -0.02em at large sizes).

## Spacing and layout

- 4px base: 4, 8, 12, 16, 24, 32, 40, 48, 64, 96 (approx.).
- Page widths: content ~1080px, docs ~768px reading width (approx.).
- Dense dashboards: rows 40–48px, tables with mono numbers, aligned on a 12-column grid.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| Radius small | 6px (approx.) | Buttons, inputs |
| Radius medium | 8px (approx.) | Cards |
| Radius large | 12px (approx.) | Modals, popovers |
| Radius full | 9999px | Badges, avatars |
| Border | 1px `gray-alpha-400` | Separation (preferred to shadows) |

Shadows are subtle and mostly for floating elements (menus, modals); flat surfaces separate with borders.

## Motion

- Fast: 150ms for hover/state (approx.), 200–250ms for popovers and modals (approx.).
- Easing: ease-out curves, e.g. `cubic-bezier(0.175, 0.885, 0.32, 1.1)` for menus (approx.).
- Spinners and skeletons for loading; `prefers-reduced-motion` turns movement into fades.

## Components

- **Button**: primary (inverted gray-1000), secondary (bordered), tertiary (ghost), error (red); sizes small 32 / medium 40 / large 48px (approx.).
- **Inputs**: bordered, 40px tall, label above, error message below in red-900 (approx.).
- **Feedback**: toasts bottom-right, `Note` callouts (success/warning/error/secondary), status dots for deployments.
- **Data**: tables with mono numbers, relative times, copy buttons for IDs.
- **Navigation**: top bar with project switcher, tabs under it; command menu (`⌘K`).
- **Empty / loading / error**: skeletons that match final layout; empty states with one action.

## Accessibility

- Gray 1000 on background 100 and the 900 text step meet 4.5:1; never use steps 100–600 for text.
- Visible focus ring (blue, 2px) on keyboard focus.
- Targets ≥ 24px; icon buttons have labels; status dots carry text.
- Respect `prefers-reduced-motion` and the system color scheme.

## Rules for agents

- Fonts from the `geist` package (`GeistSans`, `GeistMono`) or `next/font`; numbers in tables in Geist Mono or tabular figures.
- Colors from CSS variables of the gray/blue/red/amber/green scales (define them once in `tokens.css` with light and dark values); never ad-hoc hex in components.
- Separate surfaces with 1px borders before reaching for shadows.
- Primary action = inverted gray button; one per view.
- If using Tailwind/shadcn, map the scales to theme variables rather than copying values per component.
