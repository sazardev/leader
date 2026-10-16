<!-- name: Retro futurism -->
<!-- desc: Y2K chrome and gradients: iridescent accents, glossy pills, wide display type, strict contrast rules -->

# DESIGN.md: Retro futurism

A Y2K-inspired style: chrome and iridescent gradients, glossy pill buttons, wide techno display type and soft glows over
a clean base. Suits music, fashion, events, creative tools and launches. The excess lives in accents; text stays readable.

## Principles

- **Chrome on the edges, calm in the middle**: gradients and gloss on accents and heroes, plain surfaces for content.
- **Optimism**: bright, futuristic, a bit naive; never dark or grungy.
- **Contrast is non-negotiable**: text never sits on an unscrimmed gradient.
- **Shapes are capsules**: pills, ovals, rounded rectangles.
- **Glow, don't blur**: light effects are cheap gradients, not heavy filters.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#F4F6FF` | `#0A0B1A` | Page |
| `surface` | `#FFFFFF` | `#14162B` | Cards |
| `text` | `#0D0F2B` | `#F2F4FF` | Text |
| `text-muted` | `#4A4F7A` | `#AEB3D9` | Secondary |
| `chrome` | `linear-gradient(180deg, #FDFDFF 0%, #B9BED0 45%, #EEF0F8 55%, #8C92A8 100%)` | same, darker stops (approx.) | Chrome buttons, badges |
| `iridescent` | `linear-gradient(120deg, #7CF5FF, #B38CFF, #FF8CE1, #FFE08C)` | same | Hero accents, borders |
| `accent` | `#5B3CFF` | `#9C8BFF` | Primary action, links |
| `on-accent` | `#FFFFFF` | `#0A0B1A` | Text on accent |
| `glow` | `#7CF5FF` | `#7CF5FF` | Focus and hover glows |
| `success` | `#0E8F5A` | `#5CF2A8` | States |
| `warning` | `#9A6A00` | `#FFD166` | States |
| `danger` | `#C21F5B` | `#FF6FA3` | Errors |

## Typography

Display: a wide techno face (Michroma, Orbitron, Syne). Text: a clean grotesk (Inter, Space Grotesk).

| Role | Size / line height | Weight | Font | Use |
| --- | --- | --- | --- | --- |
| display | 64 / 68 | 700, uppercase, +0.02em | wide | Hero |
| h1 | 36 / 42 | 700 | wide | Titles |
| h2 | 24 / 30 | 600 | grotesk | Sections |
| body | 16 / 26 | 400 | grotesk | Text |
| label | 13 / 16 | 600, uppercase, +0.1em | grotesk | Pills, tags |

## Spacing and layout

- 4px base; scale 4, 8, 12, 16, 24, 32, 48, 80.
- Heroes centered with an iridescent backdrop; content sections on plain surfaces in a 12-column grid, max 1200px.
- Floating decorative shapes (orbs, stars) only in heroes, `aria-hidden`.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| `radius-pill` | 999px | Buttons, tags, inputs |
| `radius-card` | 24px | Cards |
| `border-iridescent` | 1.5px gradient border (`border-image` or mask) | Featured cards |
| `gloss` | `inset 0 1px 0 rgb(255 255 255 / 0.7), 0 6px 20px rgb(91 60 255 / 0.25)` | Chrome / primary buttons |
| `glow-focus` | `0 0 0 3px glow` | Focus |

## Motion

| Token | Value |
| --- | --- |
| `duration-base` | 240ms |
| `shimmer` | 2.4s linear infinite (gradient position) |
| `ease` | `cubic-bezier(0.16, 1, 0.3, 1)` |

- Chrome buttons shimmer once on hover (gradient slides); iridescent borders rotate slowly on featured cards only.
- Reduced motion: no shimmer, no rotation.

## Components

- **Primary button**: pill, `accent` fill or `chrome` with dark text, `gloss`.
- **Tag / badge**: pill, label style, chrome or tinted.
- **Featured card**: surface + `border-iridescent`, `radius-card`.
- **Inputs**: pill, 48px high, glow focus.
- **States**: empty (orb illustration + line + action), loading (iridescent progress bar), error (danger text + retry).

## Accessibility

- Never place text directly on `iridescent` or `chrome` without a solid scrim; text on chrome must be `text` with ≥ 4.5:1 at the darkest stop it crosses.
- Animated gradients pause with reduced motion and never flash (> 3 per second).
- Focus is the glow plus a 2px solid outline (glow alone may be too faint).
- Decorative shapes are `aria-hidden`.

## Rules for agents

- Gradients only from the tokens; content areas stay on plain surfaces.
- Check contrast of every text-on-gradient case at its worst stop.
- Shimmer and rotation are opt-in per component and off under reduced motion.
- Effects are CSS gradients and inset shadows, never large `filter: blur()` layers.
- Limit the wide display font to headings.
