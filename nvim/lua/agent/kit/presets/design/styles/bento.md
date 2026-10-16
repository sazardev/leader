<!-- name: Bento grid -->
<!-- desc: modular bento layouts: cards of varied spans on a strict grid, soft radii, one idea per tile -->

# DESIGN.md: Bento grid

A layout-led style: the page is a grid of rounded tiles of different spans, each tile holding one idea (a metric, a feature,
a preview). Calm neutral surfaces, one accent, generous gaps. Suits landing pages, dashboards, portfolios and feature tours.

## Principles

- **One idea per tile**: a tile says one thing; two ideas are two tiles.
- **The grid is the design**: spans and gaps are tokens, never ad-hoc sizes.
- **Hierarchy by span**: the most important tile is the largest; size, not color, signals importance.
- **Quiet surfaces**: tiles are separated by gap and tone, not by heavy borders or shadows.
- **Responsive by reflow**: tiles reflow to fewer columns; content inside never shrinks below readable.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#F5F5F4` | `#0C0C0D` | Page behind the grid |
| `surface` | `#FFFFFF` | `#18181B` | Tiles |
| `surface-raised` | `#FFFFFF` | `#202024` | Hovered / featured tile |
| `surface-tint` | `#EEF2FF` | `#1E1B4B` | Featured tile background (approx.) |
| `text` | `#18181B` | `#F4F4F5` | Text |
| `text-muted` | `#52525B` | `#A1A1AA` | Captions, labels |
| `border` | `#E7E5E4` | `#27272A` | Hairline tile edge (optional) |
| `accent` | `#4F46E5` | `#818CF8` | Primary action, focus, highlights |
| `on-accent` | `#FFFFFF` | `#0C0C0D` | Text on accent |
| `success` | `#15803D` | `#4ADE80` | States |
| `warning` | `#A16207` | `#FACC15` | States |
| `danger` | `#B91C1C` | `#F87171` | Errors |

## Typography

Font: Inter or Geist (sans), with `system-ui, -apple-system, "Segoe UI", sans-serif` fallback. Tabular figures for metrics.

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| display | 48 / 52 | 650 | Hero tile headline |
| metric | 40 / 44 | 600 | Big numbers in metric tiles |
| h2 | 24 / 30 | 600 | Section titles |
| tile-title | 18 / 24 | 600 | Tile headings |
| body | 15 / 24 | 400 | Tile copy |
| caption | 13 / 18 | 500 | Labels, metadata |

## Spacing and layout

- 4px base; scale 4, 8, 12, 16, 24, 32, 48, 64.
- Grid: 12 columns desktop (≥ 1024px), 6 tablet (640–1023), 2 mobile (< 640); gap 16px (12 on mobile); max width 1200px.
- Tile spans as tokens: `1x1`, `2x1`, `2x2`, `3x2`, `4x2`, `full` (in grid cells; a cell ≈ 1 column × 120px row).
- Tile padding 24px (16 on mobile); content aligns to the tile's top-left.
- Order tiles by importance; the hero tile starts at the top-left on every breakpoint.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| `radius-tile` | 20px | Tiles |
| `radius-inner` | 12px | Images, inner cards (tile radius − padding/2) |
| `radius-control` | 10px | Buttons, inputs |
| `shadow-none` | none | Default tiles |
| `shadow-hover` | `0 8px 24px rgb(0 0 0 / 0.08)` | Hovered interactive tile |

Inner radius = outer radius − padding so nested corners look concentric.

## Motion

| Token | Value |
| --- | --- |
| `duration-fast` | 120ms |
| `duration-base` | 200ms |
| `ease-out` | `cubic-bezier(0.2, 0.8, 0.2, 1)` |

- Tiles lift 2px and gain `shadow-hover` on hover; content inside may parallax by at most 4px.
- On load tiles fade in staggered by 40ms, top-left to bottom-right; reduced motion: no stagger, no lift.

## Components

- **Tile**: the only container; variants `plain`, `featured` (surface-tint), `media` (image fills, text on scrim), `metric` (metric + caption + sparkline).
- **Buttons**: primary (accent), secondary (surface with border), ghost; 40px high.
- **Metric tile**: number, unit, delta badge (success/danger with arrow), caption.
- **Lists inside tiles**: at most 5 rows; more goes behind a "View all" link.
- **States**: empty tile (icon + one line + action), loading (skeleton matching the tile layout), error (message + retry inside the tile).

## Accessibility

- Text contrast ≥ 4.5:1 on every tile surface, including featured and media tiles (scrim at least 50% under text).
- Reading order follows the visual order on every breakpoint (DOM order = importance order).
- Interactive tiles are a single link/button with a visible focus ring (2px accent, 2px offset); no nested interactive elements inside clickable tiles.
- Targets ≥ 44×44px.

## Rules for agents

- Build the grid with CSS Grid (`grid-template-columns: repeat(12, 1fr)`, `grid-auto-rows: 120px`) and span classes from tokens; never absolute positioning.
- Never invent a span or gap: add a token first.
- One tile component with variants; no one-off tiles.
- Keep tile content short: if it scrolls, it is two tiles or a page.
- Test the three breakpoints and the reading order with a screen reader.
