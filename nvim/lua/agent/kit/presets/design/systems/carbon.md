<!-- name: Carbon -->
<!-- desc: IBM's system: IBM Plex, 2x grid, square corners, 4 themes, productive vs expressive motion -->

# DESIGN.md: Carbon

Carbon, IBM's open-source design system for products and digital experiences. Source of truth: carbondesignsystem.com.
Every value is a token (color, type, spacing, motion) that changes with the theme (White, Gray 10, Gray 90, Gray 100);
components read tokens such as `$background`, `$layer-01`, `$text-primary`, never IBM color palette values directly.

## Principles

- **Open**: built in the open, everything documented and reusable.
- **Modular**: small components and patterns that compose into complex enterprise screens.
- **Consistent**: one grid, one type scale, one set of tokens across every product.
- **Productive by default**: dense, efficient, square; expressive moments are deliberate (marketing, onboarding).
- **Inclusive**: WCAG AA is the baseline, not an extra.

## Color

Layering model: `background` → `layer-01` → `layer-02` → `layer-03`, each a step lighter (light themes) or lighter-gray (dark).

| Token | White | Gray 100 | Use |
| --- | --- | --- | --- |
| `$background` | `#FFFFFF` | `#161616` | Page background |
| `$layer-01` | `#F4F4F4` | `#262626` | Containers on background |
| `$layer-02` | `#FFFFFF` | `#393939` | Containers on layer-01 |
| `$field-01` | `#F4F4F4` | `#262626` | Inputs on background |
| `$text-primary` | `#161616` | `#F4F4F4` | Primary text |
| `$text-secondary` | `#525252` | `#C6C6C6` | Secondary text, labels |
| `$text-placeholder` | `#A8A8A8` | `#6F6F6F` | Placeholders |
| `$text-on-color` | `#FFFFFF` | `#FFFFFF` | Text on interactive colors |
| `$border-subtle-01` | `#C6C6C6` | `#393939` | Dividers |
| `$border-strong-01` | `#8D8D8D` | `#6F6F6F` | Input bottom borders |
| `$interactive` / `$button-primary` | `#0F62FE` | `#0F62FE` | Primary actions |
| `$link-primary` | `#0F62FE` | `#78A9FF` | Links |
| `$focus` | `#0F62FE` | `#FFFFFF` | Focus border |
| `$support-error` | `#DA1E28` | `#FA4D56` | Errors |
| `$support-success` | `#24A148` | `#42BE65` | Success |
| `$support-warning` | `#F1C21B` | `#F1C21B` | Warning |
| `$support-info` | `#0043CE` | `#4589FF` | Info |

- Gray 10 (light) and Gray 90 (dark) are the other two themes; values come from `@carbon/themes`.
- Hover and active states have their own tokens (`$button-primary-hover` `#0050E6`, `$layer-hover-01`…); never darken by hand.

## Typography

Font: IBM Plex Sans (UI), IBM Plex Mono (code), IBM Plex Serif (editorial). Weights: light 300, regular 400, semibold 600.

| Token | Size / line height | Weight | Letter spacing | Use |
| --- | --- | --- | --- | --- |
| `label-01` | 12 / 16 | 400 | 0.32px | Field labels, captions |
| `helper-text-01` | 12 / 16 | 400 | 0.32px | Helper text |
| `body-compact-01` | 14 / 18 | 400 | 0.16px | Dense UI text |
| `body-01` | 14 / 20 | 400 | 0.16px | Default body text |
| `body-02` | 16 / 24 | 400 | 0 | Long-form reading |
| `heading-01` | 14 / 18 | 600 | 0.16px | Small headings |
| `heading-02` | 16 / 24 | 600 | 0 | Component headings |
| `heading-03` | 20 / 28 | 400 | 0 | Section headings |
| `heading-04` | 28 / 36 | 400 | 0 | Page headings |
| `heading-05` | 32 / 40 | 400 | 0 | Large headings |
| `heading-06` | 42 / 50 | 300 | 0 | Display |
| `heading-07` | 54 / 64 | 300 | 0 | Hero |
| `code-01` | 12 / 16 | 400 (Mono) | 0.32px | Inline code |

Fluid variants (`fluid-heading-03`…) scale with the breakpoint on expressive pages only.

## Spacing and layout

- Spacing tokens: `$spacing-01` 2, `02` 4, `03` 8, `04` 12, `05` 16, `06` 24, `07` 32, `08` 40, `09` 48, `10` 64, `11` 80, `12` 96, `13` 160 (px).
- 2x Grid: 16 columns at large and up (4 at sm, 8 at md); gutter 32px (16 each side); margins grow with the breakpoint.
- Breakpoints: `sm` 320, `md` 672, `lg` 1056, `xlg` 1312, `max` 1584 (px).
- Component heights: small 32, medium 40 (default), large 48.

## Shape and elevation

- **Square corners**: border radius 0 on buttons, inputs, tiles, modals. Only tags, toggles and some indicators are rounded.
- Separation comes from **layers** (background tone steps), not shadows. Shadows only on floating elements: menus, dropdown lists, tooltips, popovers, modals (`box-shadow: 0 2px 6px rgba(0,0,0,0.3)`, approx.).
- Inputs: filled with a 1px bottom border (`$border-strong-01`); focus = 2px `$focus` outline inside.

## Motion

| Token | Value | Use |
| --- | --- | --- |
| `$duration-fast-01` | 70ms | Micro-interactions: button, toggle |
| `$duration-fast-02` | 110ms | Fade, small expansions |
| `$duration-moderate-01` | 150ms | Dropdowns, tooltips |
| `$duration-moderate-02` | 240ms | Accordions, side panels |
| `$duration-slow-01` | 400ms | Large expansions, modals |
| `$duration-slow-02` | 700ms | Background/hero transitions |
| standard productive | `cubic-bezier(0.2, 0, 0.38, 0.9)` | Elements moving on screen |
| entrance productive | `cubic-bezier(0, 0, 0.38, 0.9)` | Elements appearing |
| exit productive | `cubic-bezier(0.2, 0, 1, 0.9)` | Elements leaving |
| standard expressive | `cubic-bezier(0.4, 0.14, 0.3, 1)` | Significant, attention moments |
| entrance expressive | `cubic-bezier(0, 0, 0.3, 1)` | |
| exit expressive | `cubic-bezier(0.4, 0.14, 1, 1)` | |

- Productive motion for everyday product UI (fast, subtle); expressive only for important moments (first-time, success, marketing).
- Respect `prefers-reduced-motion`: Carbon components drop transitions automatically; custom ones must too.

## Components

- **Buttons**: primary (one per area), secondary, tertiary (outline), ghost, danger. Primary on the right in button groups; full-width buttons in modals and side panels.
- **Forms**: label above the field, helper text below, error replaces helper with an icon; `invalid` + `invalidText`. Fluid forms for dense layouts.
- **Data table**: the core enterprise component: toolbar (search, batch actions), sortable headers, expandable rows, pagination below; sizes xs–xl.
- **Navigation**: UI Shell (header + side nav), tabs for views, breadcrumb for depth.
- **Modals**: passive, transactional, danger; never stack modals; side panels for longer tasks.
- **Notifications**: inline (in context), toast (transient), actionable; plus empty states and skeleton states for loading.

## Accessibility

- WCAG 2.1 AA (IBM Accessibility Checklist): text 4.5:1, UI 3:1; all theme token pairs pass, custom combinations must be checked.
- Focus: 2px `$focus` border (plus inset `$focus-inset` on colored backgrounds), always visible on keyboard focus.
- Every component is keyboard operable following the WAI-ARIA authoring practices; tables announce sort state.
- Never color alone for status: notifications and tags carry an icon and text.
- Targets ≥ 24×24px; prefer medium (40px) controls on touch.

## Rules for agents

- Use `@carbon/react` (or `@carbon/web-components`) with `@carbon/styles`; wrap the app in `<Theme theme="white|g10|g90|g100">` and nest `Layer` for layering.
- Styles via Sass tokens (`@use '@carbon/styles/scss/theme' as *;` then `$layer-01`, `$text-primary`) or CSS variables `--cds-*`; never hex values or `@carbon/colors` in components.
- Spacing with `$spacing-0X`, type with `@include type-style('body-01')`; never raw px for either.
- Layout with the `Grid`/`Column` components (2x grid), not ad-hoc flex widths.
- Keep corners square and depth flat (layers), unless the component itself is rounded.
- Use productive motion tokens by default; expressive only where the design calls for it.
- Icons from `@carbon/icons-react` at 16 or 20px, pictograms only for illustrative content.
