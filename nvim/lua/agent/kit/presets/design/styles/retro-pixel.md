<!-- name: Retro pixel -->
<!-- desc: 8/16-bit pixel aesthetics: pixel fonts, limited palettes, stepped 2px borders, dithering, crisp scaling -->

# DESIGN.md: Retro pixel

An 8/16-bit game-console look for apps and sites: pixel fonts, a limited palette, stepped borders drawn in whole pixels,
dithered shading and crisp integer scaling. Fun and nostalgic, with modern accessibility underneath.

## Principles

- **Whole pixels only**: sizes, borders and offsets are multiples of the pixel unit (2px or 4px); nothing half-pixel.
- **Limited palette**: 16 colors at most, like a console; shading by dithering, not gradients.
- **Crisp scaling**: art scales by integers with nearest-neighbor, never smoothed.
- **Game-like feedback**: presses, sounds (optional) and small sprite animations reward actions.
- **Readable text**: pixel fonts for display, a clean font for long text.

## Color

Base palette PICO-8-inspired (approx.); swap for any 16-color palette (Sweetie 16, DB16) with the same roles.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#FFF1E8` | `#1D2B53` | Page |
| `surface` | `#FFFFFF` | `#7E2553` (approx. as panel) | Panels |
| `ink` | `#000000` | `#FFF1E8` | Text, borders |
| `text-muted` | `#5F574F` | `#C2C3C7` | Secondary |
| `primary` | `#29ADFF` | `#29ADFF` | Main actions |
| `on-primary` | `#000000` | `#000000` | Text on primary |
| `accent` | `#FFEC27` | `#FFEC27` | Highlights, coins |
| `success` | `#00E436` | `#00E436` | Success |
| `warning` | `#FFA300` | `#FFA300` | Warnings |
| `danger` | `#FF004D` | `#FF004D` | Errors, hearts |
| `focus` | `#FFEC27` 4px stepped | `#FFEC27` | Focus |

## Typography

| Role | Size / line height | Font | Use |
| --- | --- | --- | --- |
| display | 32 / 40 | Press Start 2P (approx.) | Titles |
| h1 | 24 / 32 | Press Start 2P | Page titles |
| h2 | 16 / 24 | Press Start 2P | Sections |
| body | 18 / 28 | VT323 or Silkscreen for short text; Inter for long text | Text |
| label | 12 / 16 | Press Start 2P, uppercase | Buttons |

- Pixel fonts only at their native size multiples (8, 16, 24, 32px) with `-webkit-font-smoothing: none` (approx. effect varies by browser).

## Spacing and layout

- Pixel unit 4px; scale 4, 8, 12, 16, 24, 32, 48, 64.
- Layout grid 8px; max width 1024px (like a big screen) centered; breakpoints 480, 768, 1024.
- Mobile: same unit, single column, HUD-like bottom bar for main actions.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| border | 4px `ink`, stepped corners (corner pixels removed) via `clip-path` or border-image | Panels, buttons |
| radius | 0 (corners stepped, never rounded) | Everything |
| shadow | `4px 4px 0 ink` or a 4px darker bottom edge | Buttons, cards |
| dither | 2×2 checker pattern from two palette colors | Shading, disabled states |

## Motion

| Token | Value | Use |
| --- | --- | --- |
| frame-rate | sprite animations at 8–12 fps (steps) | Characters, icons |
| easing | `steps(4)` or `steps(8)` | Movement |
| press | 100ms, translate 4px down, shadow 0 | Buttons |
| blink | 2 Hz cursor `▮` | Text inputs, prompts |

- Reduced motion: sprites static on their first frame, no blinking.

## Components

- **Buttons**: stepped border, `primary` fill, pixel label, pressed moves down 4px.
- **Inputs**: dark field, blinking block cursor, pixel label above.
- **Dialogs**: RPG text box: stepped frame, text typed in (skippable), `▼` to continue.
- **Progress**: segmented bar (8px segments) or hearts/coins counters.
- **Lists/menus**: `▶` cursor marking the selection, keyboard navigable.
- **Toasts**: "achievement" banner sliding from the top.
- **Empty/loading/error**: sprite + one line; loading as a walking sprite or segmented bar.

## Accessibility

- Long text never in pixel fonts; minimum 16px for any pixel font text.
- Contrast pairs from the palette checked ≥ 4.5:1 (e.g. `#000000` on `#29ADFF` ≈ 8:1, approx.).
- Sounds off by default, with a visible toggle.
- Typewriter text can be skipped; reduced motion disables sprites and blinking.

## Rules for agents

- Images: `image-rendering: pixelated`; scale assets only by integers.
- All sizes are multiples of the 4px unit; tokens as CSS variables, palette in one file.
- Shading by dither patterns from palette colors, never CSS gradients or blur.
- Use the clean font for paragraphs; pixel fonts for display and labels.
