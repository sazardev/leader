<!-- name: Neo-brutalism -->
<!-- desc: thick black borders, hard offset shadows, flat saturated fills, chunky type; loud and playful -->

# DESIGN.md: Neo-brutalism

A loud, playful GUI style: flat saturated fills, 2–3px black outlines on everything, hard offset shadows with no blur and
chunky grotesk type. Elements look like stickers on paper. It suits marketing sites, creative tools and indie products.

## Principles

- **Outlines everywhere**: every interactive element has a black border; that is the style's grammar.
- **Hard shadows, no blur**: depth is an offset black block, never a soft shadow.
- **Flat, saturated color**: big fields of a few bright colors on an off-white paper.
- **Chunky and direct**: heavy type, short copy, obvious buttons.
- **Playful press**: pressing an element moves it into its shadow.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#FFFDF5` | `#121212` | Page |
| `surface` | `#FFFFFF` | `#1E1E1E` | Cards |
| `ink` | `#000000` | `#FFFFFF` | Text, borders, shadows (dark: borders white, shadows black) |
| `text-muted` | `#3D3D3D` | `#C8C8C8` | Secondary text |
| `primary` | `#FF6B6B` | `#FF6B6B` | Main actions |
| `on-primary` | `#000000` | `#000000` | Text on primary |
| `accent-yellow` | `#FFD23F` | `#FFD23F` | Highlights, badges |
| `accent-blue` | `#4D96FF` | `#4D96FF` | Links, info |
| `accent-green` | `#6BCB77` | `#6BCB77` | Success |
| `danger` | `#FF3B3B` | `#FF5C5C` | Errors |
| `focus` | `#000000` 3px + offset | `#FFFFFF` 3px | Focus ring |

- Text on fills is always `ink` black (bright fills keep ≥ 4.5:1 with black, approx.; verify each pair).

## Typography

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| display | 64 / 68 | 800 | Heroes |
| h1 | 40 / 44 | 800 | Page titles |
| h2 | 28 / 32 | 700 | Sections |
| h3 | 20 / 26 | 700 | Cards |
| body | 16 / 24 | 500 | Text |
| small | 14 / 20 | 500 | Meta |
| label | 14 / 16 | 700, uppercase | Buttons, badges |

- Fonts: Space Grotesk, Archivo Black or Lexend Mega for display; Inter or Public Sans for body (approx. common pairings).

## Spacing and layout

- 4px base; scale 4, 8, 12, 16, 24, 32, 48, 64, 96.
- 12-column grid, 24px gutters, max content width 1200px; breakpoints 640, 768, 1024, 1280.
- Cards in loose grids with visible gaps (24–32px); elements may be slightly rotated (±2°) on marketing pages only.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| border | 3px solid `ink` (2px on small controls) | Everything interactive, cards |
| radius-none | 0 | Default |
| radius-sm | 6px | Optional softer variant |
| shadow-sm | `3px 3px 0 0 ink` | Inputs, chips |
| shadow-md | `5px 5px 0 0 ink` | Buttons, cards |
| shadow-lg | `8px 8px 0 0 ink` | Dialogs, heroes |

- Never blur a shadow; never use gradients.

## Motion

| Token | Value | Use |
| --- | --- | --- |
| duration-fast | 100ms | Press |
| duration-base | 160ms | Hover, toggles |
| easing | `cubic-bezier(0.2, 0.8, 0.2, 1)` | Everything |
| press | translate(+shadow offset) and shadow 0 | Buttons, cards |
| hover | translate(-1px, -1px), shadow +1px | Pointer devices |

- Reduced motion: no translate; state shown by color and shadow change only.

## Components

- **Buttons**: fill `primary`, 3px border, `shadow-md`, uppercase label; pressed = moves into the shadow.
- **Inputs**: white fill, 3px border, `shadow-sm`, label above in bold; error = `danger` border + message.
- **Cards**: `surface`, border, `shadow-md`, optional colored header band.
- **Tables**: bordered cells, header row `accent-yellow`.
- **Navigation**: top bar with bordered bottom edge; active item underlined 3px.
- **Dialogs**: `shadow-lg`, title band in an accent color.
- **Toasts**: bordered stickers at a corner, auto-dismiss 5s.
- **Empty/loading/error**: illustration or big emoji-free glyph, bold sentence, one button; skeletons are bordered blocks.

## Accessibility

- WCAG 2.2 AA: all text pairs ≥ 4.5:1; borders give non-color affordances (3:1 against background by construction).
- Focus: 3px `focus` outline offset 3px, never removed.
- Targets ≥ 44×44px.
- Rotation and motion off with `prefers-reduced-motion`.

## Rules for agents

- Tokens as CSS custom properties (`--ink`, `--shadow-md`…) or a Tailwind theme; never literal hex or shadows in components.
- Every interactive element has border + shadow from tokens; the press state is mandatory.
- No blur, no gradients, no thin 1px borders.
- Dark mode swaps `background/surface/ink`; accents stay.
