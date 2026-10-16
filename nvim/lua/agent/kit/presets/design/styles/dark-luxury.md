<!-- name: Dark luxury -->
<!-- desc: deep blacks, champagne gold accent, refined serif display, wide spacing, slow elegant motion -->

# DESIGN.md: Dark luxury

A premium dark style: near-black layers, a single champagne-gold accent, a refined serif for display, thin rules and a
lot of air. Suits high-end retail, hospitality, finance and portfolios where restraint signals quality.

## Principles

- **Restraint is luxury**: few elements, generous space, nothing shouts.
- **One metal**: gold appears only on what matters (primary action, key figures, dividers).
- **Depth by tone**: layers are close blacks, not shadows.
- **Slow and smooth**: motion is unhurried and subtle.
- **Imagery leads**: photography carries emotion; UI frames it.

## Color

Dark is the primary theme; the light variant is an "ivory" option.

| Token | Dark | Ivory (light) | Use |
| --- | --- | --- | --- |
| `background` | `#0B0B0C` | `#F7F3EC` | Page |
| `surface` | `#141416` | `#FFFDF8` | Sections, cards |
| `surface-raised` | `#1C1C1F` | `#FFFFFF` | Menus, dialogs |
| `text` | `#F2EEE6` | `#1A1814` | Text |
| `text-muted` | `#A39E94` | `#6B655B` | Secondary text |
| `rule` | `#2C2A27` | `#E2DACB` | Hairlines |
| `gold` | `#C9A96E` | `#9C7A3C` | Accent: primary action, key numbers, rules |
| `gold-soft` | `#E6D3A8` | `#C9A96E` | Hover, highlights |
| `on-gold` | `#0B0B0C` | `#FFFFFF` | Text on gold |
| `success` | `#7FBF9A` | `#2E6B4A` | States (muted) |
| `warning` | `#D9B46A` | `#8A6516` | States |
| `danger` | `#D98080` | `#A33A3A` | Errors |

## Typography

Display: Cormorant Garamond or Playfair Display (light/regular). Text/UI: a quiet sans (Inter, Manrope) at light weights.

| Role | Size / line height | Weight | Font | Use |
| --- | --- | --- | --- | --- |
| display | 72 / 76 | 300 | serif | Hero |
| h1 | 48 / 54 | 400 | serif | Titles |
| h2 | 30 / 38 | 400 | serif | Sections |
| eyebrow | 12 / 16 | 500, uppercase, +0.24em | sans | Labels above titles |
| body | 16 / 28 | 300 | sans | Text |
| ui | 14 / 20 | 400, +0.02em | sans | Buttons, nav |
| price | 22 / 28 | 400, tabular | serif | Prices, key figures |

## Spacing and layout

- 8px base; scale 8, 16, 24, 40, 64, 96, 128.
- Sections separated by 96–128px; content max width 1200px; text blocks ≤ 560px.
- Asymmetric layouts: image 7 columns, text 4 with 1 column of air.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| `radius` | 0–2px | Buttons, inputs, images |
| `rule` | 1px `rule` | Section dividers, form underlines |
| `rule-gold` | 1px `gold`, 48px wide | Under eyebrows |
| `shadow` | none | Layering by tone only |

## Motion

| Token | Value |
| --- | --- |
| `duration-base` | 400ms |
| `duration-slow` | 800ms |
| `ease` | `cubic-bezier(0.22, 1, 0.36, 1)` |

- Images fade and scale from 1.04 to 1 on reveal; text fades up 12px; staggered 80ms.
- Hover on buttons: gold line grows under the label. Reduced motion: opacity only.

## Components

- **Primary button**: outline 1px gold, gold text, uppercase ui; hover fills gold with `on-gold` text.
- **Secondary**: text link with gold underline on hover.
- **Inputs**: underline only (1px rule), label as eyebrow; focus line becomes gold.
- **Product card**: full-bleed image, eyebrow, serif name, price; no borders.
- **Navigation**: centered logo, sparse links, menu as a full-screen overlay.
- **States**: empty (one serif line + a quiet action), loading (thin gold progress line at the top), error (muted danger text, calm wording).

## Accessibility

- Gold on black (`#C9A96E` on `#0B0B0C`) ≈ 9:1 for text; check gold on surface variants and on images (use a scrim).
- Light weights only at ≥ 16px; never 300 weight below 16px.
- Focus: 1px gold outline + 2px offset, always visible.
- Reduced motion respected for every reveal.

## Rules for agents

- Gold is reserved: primary action, key figures and rules; never backgrounds of large areas.
- No shadows, no gradients, no rounded corners beyond 2px.
- Keep text blocks narrow (≤ 560px) and sections widely spaced.
- Use the serif only for display and prices; UI text is the sans.
- Every image has alt text and a scrim when text sits on it.
