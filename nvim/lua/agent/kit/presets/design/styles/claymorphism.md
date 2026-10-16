<!-- name: Claymorphism -->
<!-- desc: soft 3D clay: pastel fills, outer + inner shadows, big radii, with contrast and performance limits -->

# DESIGN.md: Claymorphism

A soft, tactile style: elements look like inflated clay, built from a pastel fill, a soft outer shadow and two inner
shadows (light top-left, dark bottom-right). Friendly and playful; suits onboarding, consumer apps, kids' and wellness
products. Its risks (low contrast, heavy shadows) are handled by explicit rules below.

## Principles

- **Tactile, not noisy**: depth only on interactive elements and key cards, never on every box.
- **Pastel surfaces, dark text**: the softness is in the surfaces; text stays high contrast.
- **Round everything**: no sharp corners anywhere.
- **Press feedback**: pressing flattens the clay (inner shadow swaps), so the state is felt.
- **Performance budget**: shadows are few and static; no animated blur.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#F3EEFF` | `#1B1730` | Page |
| `clay-lilac` | `#D9CCFF` | `#4B3F86` | Primary clay surface |
| `clay-mint` | `#C8F2E1` | `#245E4C` | Secondary surface |
| `clay-peach` | `#FFD9C7` | `#7A4433` | Tertiary surface |
| `clay-sky` | `#CFE6FF` | `#2E4F7A` | Info surface |
| `text` | `#24193F` | `#F4F0FF` | Text on every clay surface |
| `text-muted` | `#5B5078` | `#C9C0E8` | Secondary text |
| `accent` | `#6D4AFF` | `#B3A1FF` | Primary action |
| `on-accent` | `#FFFFFF` | `#1B1730` | Text on accent |
| `success` | `#1E7F55` | `#6EE7B7` | States |
| `warning` | `#9A6400` | `#FCD34D` | States |
| `danger` | `#C02646` | `#FDA4AF` | Errors |

Shadow colors are tints of the surface, never pure black: `shade` = surface darkened 12% (OKLCH L −0.12), `light` = white at 60%.

## Typography

Font: Nunito or Quicksand (rounded sans), fallback `ui-rounded, "SF Pro Rounded", system-ui, sans-serif`.

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| display | 44 / 50 | 800 | Heroes |
| h1 | 32 / 38 | 800 | Titles |
| h2 | 22 / 28 | 700 | Sections |
| body | 16 / 26 | 500 | Text |
| label | 14 / 20 | 700 | Buttons, chips |
| caption | 13 / 18 | 600 | Hints |

## Spacing and layout

- 4px base; scale 4, 8, 12, 16, 24, 32, 48.
- Generous padding: cards 24px, buttons 14px × 24px; clay needs room for its shadow (≥ 16px between clay elements).
- Max content width 1040px; single column under 640px.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| `radius-sm` | 14px | Chips, inputs |
| `radius-md` | 22px | Buttons |
| `radius-lg` | 32px | Cards, sheets |
| `clay-raised` | `8px 8px 16px shade, inset -6px -6px 12px shade, inset 6px 6px 12px light` | Cards, buttons at rest |
| `clay-pressed` | `inset 6px 6px 12px shade, inset -4px -4px 8px light` | Pressed / selected |
| `clay-flat` | none | Text areas, long lists |

At most 6 clay-raised elements per viewport (performance and visual noise).

## Motion

| Token | Value |
| --- | --- |
| `duration-press` | 120ms |
| `duration-base` | 220ms |
| `spring` | `cubic-bezier(0.34, 1.56, 0.64, 1)` (overshoot) |

- Press: `clay-raised` → `clay-pressed` and scale 0.97; release springs back.
- Enter: scale from 0.92 with `spring`. Reduced motion: no scale, instant shadow swap.

## Components

- **Button**: clay surface + `clay-raised`; primary uses `accent` fill with the same shadow recipe on accent tints.
- **Card**: `radius-lg`, `clay-raised`, pastel surface; content inside is flat.
- **Input**: `clay-pressed` (looks carved in), 48px high, visible label above.
- **Toggle / chip**: selected = pressed shadow + accent text.
- **States**: empty (illustration on clay card + one action), loading (pulsing clay skeleton, reduced motion: static), error (danger text + retry).

## Accessibility

- Contrast is measured on the pastel fill: text ≥ 4.5:1; never put muted text on mid-tone clay.
- Shadows are not the only state cue: selected also changes text weight/color; focus ring 3px `accent` outside the clay.
- `prefers-contrast: more` → borders 2px `text` color, shadows removed.
- Targets ≥ 48×48px.

## Rules for agents

- Use the three shadow tokens only; never write a box-shadow by hand.
- Clay only on interactive elements and top-level cards; lists, tables and long text are flat.
- Shadow colors derive from the surface token, never `rgba(0,0,0,…)`.
- Check contrast on each pastel before shipping a new color pair.
- Implement tokens as CSS custom properties; the dark theme swaps the surfaces and shade tints.
