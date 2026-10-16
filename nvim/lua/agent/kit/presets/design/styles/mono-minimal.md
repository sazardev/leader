<!-- name: Mono minimal -->
<!-- desc: monochrome minimal: black, white and grays, one accent, typography-led, generous whitespace -->

# DESIGN.md: Mono minimal

A quiet monochrome style: black, white and a gray ramp, one accent used sparingly, typography doing the work and generous
whitespace. Calm, timeless and fast to build; suits tools, docs, portfolios and dashboards that want to disappear.

## Principles

- **Grays do the hierarchy**: importance is expressed with the gray ramp and weight, not color.
- **One accent, rarely**: the accent marks the primary action and focus, nothing else.
- **Typography first**: a great type scale replaces decoration.
- **Space is structure**: generous margins separate groups instead of boxes.
- **Nothing extra**: no shadows unless something floats, no gradients, no illustration by default.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#FFFFFF` | `#0A0A0A` | Page |
| `surface` | `#FAFAFA` | `#111111` | Sections |
| `surface-raised` | `#FFFFFF` | `#171717` | Menus, dialogs |
| `gray-100` | `#F4F4F5` | `#1C1C1E` | Hover |
| `gray-300` | `#D4D4D8` | `#3F3F46` | Borders |
| `gray-500` | `#71717A` | `#A1A1AA` | Muted text |
| `text` | `#0A0A0A` | `#FAFAFA` | Text |
| `accent` | `#2563EB` (swap for brand) | `#60A5FA` | Primary action, focus, links |
| `on-accent` | `#FFFFFF` | `#0A0A0A` | Text on accent |
| `success` | `#15803D` | `#4ADE80` | States |
| `warning` | `#A16207` | `#FACC15` | States |
| `danger` | `#B91C1C` | `#F87171` | Errors |

## Typography

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| display | 56 / 60 | 600 | Heroes |
| h1 | 36 / 44 | 600 | Page titles |
| h2 | 24 / 32 | 600 | Sections |
| h3 | 18 / 28 | 600 | Subsections |
| body | 16 / 26 | 400 | Text |
| small | 14 / 22 | 400 | Meta |
| mono | 14 / 22 | 400 | Code, IDs, numbers in tables |

- Fonts: Inter or Geist for UI, Geist Mono or JetBrains Mono for code (approx. choices; one sans + one mono).

## Spacing and layout

- 4px base; scale 4, 8, 12, 16, 24, 32, 48, 64, 96, 128.
- 12-column grid, 24px gutters; reading width 680px; app max width 1280px; breakpoints 640, 768, 1024, 1280.
- Sections separated by 64–128px; related items by 8–16px.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| radius-sm | 6px | Inputs, buttons |
| radius-md | 10px | Cards, menus |
| border | 1px `gray-300` | Dividers, inputs |
| shadow-float | `0 8px 24px rgba(0,0,0,0.08)` (dark: border only) | Menus, dialogs |

## Motion

| Token | Value | Use |
| --- | --- | --- |
| duration-fast | 120ms | Hover, toggles |
| duration-base | 200ms | Menus, dialogs |
| easing | `cubic-bezier(0.2, 0, 0, 1)` | Everything |

- Fades and 4px slides only; reduced motion = instant.

## Components

- **Buttons**: primary = `text` fill with `background` label (or `accent` when it is the one key action); secondary = 1px border; ghost = text only.
- **Inputs**: 1px border, 40px height, label above, error text below in `danger`.
- **Navigation**: text links, active one in `text` weight 600, others `gray-500`.
- **Tables**: no stripes, 1px row dividers, numbers in mono right-aligned.
- **Cards**: only when grouping is needed; border, no shadow.
- **Dialogs/menus**: `surface-raised` + `shadow-float`.
- **Toasts**: dark pill (`text` background), bottom center.
- **Empty/loading/error**: one sentence + action; skeletons in `gray-100`.

## Accessibility

- AA contrast: `gray-500` on white ≈ 4.8:1 (approx.), never lighter for text.
- Focus: 2px `accent` outline offset 2px.
- Links underlined (color alone is not enough in a monochrome UI).
- Targets ≥ 44×44px.

## Rules for agents

- Tokens as CSS variables or a Tailwind theme with the gray ramp; no other colors besides accent and states.
- Hierarchy through the type scale and grays, never by adding color.
- One accented element per view at most.
- No shadows except floating layers; no gradients; no decorative icons.
