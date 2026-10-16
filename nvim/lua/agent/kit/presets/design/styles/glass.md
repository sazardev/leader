<!-- name: Glass -->
<!-- desc: translucent materials: backdrop blur, layered panes, light edges; with performance and contrast rules -->

# DESIGN.md: Glass

A translucent-material style (macOS/visionOS vibrancy, iOS 26 Liquid Glass, Windows Mica/Acrylic): panes of frosted glass
over rich backgrounds, light edges, depth by layering. Beautiful when restrained; this file sets the limits that keep it
readable and fast.

## Principles

- **Glass is for chrome, not content**: navigation, toolbars, sheets and popovers are glass; reading surfaces are solid.
- **Depth by layering**: each layer is more opaque and more blurred than the one below.
- **Contrast is guaranteed**: text sits on a tinted layer that keeps 4.5:1 whatever is behind.
- **Light edges**: a 1px inner highlight defines each pane.
- **Performance budget**: few blurred layers on screen; fallbacks where blur is slow or unsupported.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | wallpaper or gradient `#E9EEF8 → #F8E9F1` (approx.) | `#0B1020 → #1B1033` (approx.) | Behind everything |
| `glass-thin` | `rgba(255,255,255,0.45)` | `rgba(30,30,40,0.40)` | Toolbars |
| `glass-regular` | `rgba(255,255,255,0.65)` | `rgba(30,30,40,0.60)` | Sidebars, popovers |
| `glass-thick` | `rgba(255,255,255,0.82)` | `rgba(24,24,32,0.80)` | Sheets, dialogs |
| `surface` | `#FFFFFF` | `#16161D` | Solid reading areas |
| `text` | `#0B0B0F` | `#F5F5F7` | Text |
| `text-muted` | `rgba(11,11,15,0.62)` | `rgba(245,245,247,0.65)` | Secondary |
| `edge` | `rgba(255,255,255,0.7)` inner 1px | `rgba(255,255,255,0.18)` | Pane highlight |
| `primary` | `#0A84FF` | `#409CFF` | Actions |
| `on-primary` | `#FFFFFF` | `#FFFFFF` | Text on primary |
| `success` | `#1E9E50` | `#32D74B` | States |
| `warning` | `#B26A00` | `#FFD60A` | States |
| `danger` | `#D70015` | `#FF453A` | Errors |
| `focus` | `#0A84FF` 2px + 2px halo | `#409CFF` | Focus |

## Typography

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| large-title | 34 / 41 | 700 | Screen titles |
| title | 22 / 28 | 600 | Sections |
| headline | 17 / 22 | 600 | Card titles |
| body | 17 / 24 | 400 | Text |
| callout | 15 / 20 | 400 | Secondary |
| caption | 12 / 16 | 400 | Meta |

- Fonts: system UI (`-apple-system, "SF Pro", "Segoe UI Variable", Inter, sans-serif`). Text on glass uses weight ≥ 400 and never thin weights.

## Spacing and layout

- 4px base; scale 4, 8, 12, 16, 20, 24, 32, 48.
- Floating panes inset 8–16px from screen edges; content padding 16–24px.
- Breakpoints 600, 900, 1200; mobile uses bottom glass tab bar and full-height glass sheets.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| radius-sm | 10px | Controls |
| radius-md | 16px | Popovers, cards |
| radius-lg | 24px | Sheets, panels |
| blur-thin | `backdrop-filter: blur(12px) saturate(160%)` | Toolbars |
| blur-regular | `blur(20px) saturate(180%)` | Sidebars, popovers |
| blur-thick | `blur(32px) saturate(180%)` | Sheets |
| shadow | `0 8px 32px rgba(0,0,0,0.18)` | Floating panes |
| edge | `inset 0 1px 0 edge` | Every glass pane |

- Max 3 blurred layers visible at once.

## Motion

| Token | Value | Use |
| --- | --- | --- |
| duration-fast | 150ms | Hover, press |
| duration-base | 250ms | Panes in/out |
| spring | stiffness 300, damping 30 (approx.) | Sheets, popovers |
| easing | `cubic-bezier(0.25, 0.1, 0.25, 1)` | Opacity, blur changes |

- Glass panes fade + scale from 0.98; reduced motion = fade only. Never animate `backdrop-filter` radius continuously.

## Components

- **Toolbars/nav bars**: `glass-thin`, sticky, content scrolls under them.
- **Sidebars**: `glass-regular` over the wallpaper; list items with a translucent selection pill.
- **Sheets/dialogs**: `glass-thick`, `radius-lg`, scrim `rgba(0,0,0,0.25)` behind.
- **Cards with reading content**: solid `surface`, not glass.
- **Buttons**: primary solid `primary`; secondary glass pill with `edge`.
- **Inputs**: solid `surface` with 1px border; never glass behind text entry.
- **Toasts**: small glass capsules.
- **Empty/loading/error**: solid surfaces; skeletons solid, not shimmering glass.

## Accessibility

- `prefers-reduced-transparency`: replace glass by solid `surface` tones of the same tint.
- `prefers-contrast: more`: opacity of every glass token +0.2 and borders 1px solid.
- Contrast measured against the worst-case background behind each pane; tint up until text ≥ 4.5:1.
- Reduced motion: no scale or spring.

## Rules for agents

- Glass only for chrome; content areas use `surface`.
- Every `backdrop-filter` has a `@supports not (backdrop-filter: blur(1px))` fallback with an opaque tint.
- Tokens as CSS variables; never hardcode rgba or blur values in components.
- Budget: ≤ 3 blurred layers visible, none inside scrolling lists; profile on a mid-range phone.
- SwiftUI: `.ultraThinMaterial`/`.regularMaterial`/`.thickMaterial` (and Liquid Glass APIs where available); Windows: Mica/Acrylic.
