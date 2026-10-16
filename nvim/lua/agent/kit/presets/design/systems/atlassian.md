<!-- name: Atlassian -->
<!-- desc: Atlassian Design System: semantic design tokens, elevation surfaces, 8px grid, @atlaskit components -->

# DESIGN.md: Atlassian

The Atlassian Design System (Jira, Confluence, Trello). Source of truth: atlassian.design. Every value is a **design token**
(`token('color.text')`), never a raw hex; light and dark themes are token themes switched with `setGlobalTheme`.

## Principles

- **Bold**: clear hierarchy, confident use of color for meaning, never decoration.
- **Optimistic**: positive, helpful language and states; errors explain how to recover.
- **Practical**: dense, work-focused layouts; the fastest path for the frequent task.
- **Tokens over values**: components read semantic tokens (`color.background.brand.bold`), so themes and modes are free.
- **Accessible by default**: token pairs are designed to meet WCAG 2.1 AA.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `color.text` | `#172B4D` | `#B6C2CF` | Body text |
| `color.text.subtle` | `#44546F` | `#9FADBC` | Secondary text |
| `color.text.subtlest` | `#626F86` | `#8C9BAB` | Placeholders, metadata |
| `color.text.brand` | `#0C66E4` | `#579DFF` | Brand-colored text |
| `color.link` | `#0C66E4` | `#579DFF` | Links |
| `color.background.brand.bold` | `#0C66E4` | `#579DFF` | Primary buttons |
| `color.text.inverse` | `#FFFFFF` | `#1D2125` | Text on bold backgrounds |
| `color.background.neutral` | `#091E420F` | `#A1BDD914` | Default buttons, tags |
| `color.background.danger.bold` | `#C9372C` | `#F87168` | Destructive buttons |
| `color.background.success.bold` | `#1F845A` | `#4BCE97` | Success lozenges |
| `color.background.warning.bold` | `#F5CD47` | `#F5CD47` | Warning lozenges |
| `color.border` | `#091E4224` | `#A6C5E229` | Dividers, inputs |
| `color.border.focused` | `#388BFF` | `#85B8FF` | Focus rings |
| `elevation.surface` | `#FFFFFF` | `#22272B` | Page background |
| `elevation.surface.sunken` | `#F7F8F9` | `#161A1D` | Columns, wells |
| `elevation.surface.raised` | `#FFFFFF` | `#22272B` | Cards (with shadow) |
| `elevation.surface.overlay` | `#FFFFFF` | `#282E33` | Modals, menus |

- Status uses the semantic families (`danger`, `warning`, `success`, `information`, `discovery`) with `subtlest/subtler/subtle/bold` steps.
- Interaction states have their own tokens (`color.background.neutral.hovered`, `.pressed`), never computed opacities.

## Typography

Font: Atlassian Sans (system stack fallback `ui-sans-serif, -apple-system, "Segoe UI", Roboto`); code: Atlassian Mono.

| Role (token) | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| `font.heading.xxlarge` | 32 / 36 | 653 | Page hero |
| `font.heading.xlarge` | 28 / 32 | 653 | Page title |
| `font.heading.large` | 24 / 28 | 653 | Section title |
| `font.heading.medium` | 20 / 24 | 653 | Card title |
| `font.heading.small` | 16 / 20 | 653 | Group title |
| `font.heading.xsmall` | 14 / 20 | 653 | Small headings |
| `font.body.large` | 16 / 24 | 400 | Long-form text |
| `font.body` | 14 / 20 | 400 | Default UI text |
| `font.body.small` | 12 / 16 | 400 | Metadata |
| `font.code` | 0.875em | 400 | Inline code |

Weights 653 are Atlassian Sans variable weights (approx. for system fonts: 600). Use tabular numbers in tables.

## Spacing and layout

- 8px grid with half steps: `space.025` 2, `space.050` 4, `space.075` 6, `space.100` 8, `space.150` 12, `space.200` 16, `space.250` 20, `space.300` 24, `space.400` 32, `space.500` 40, `space.600` 48, `space.800` 64, `space.1000` 80.
- Page layout: top navigation 56px, side navigation 240px (approx.), content max width ~1280px with 12-column grid.
- Density: compact lists and tables (row 40px) are the norm for work views.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| `border.radius.050` | 2px | Lozenges, badges |
| `border.radius` (`.100`) | 4px | Buttons, inputs |
| `border.radius.200` | 8px | Cards |
| `border.radius.300` | 12px | Modals |
| `border.radius.circle` | 50% | Avatars |
| `border.width` | 1px | Inputs |
| `border.width.outline` | 2px | Focus rings |

Elevation pairs a surface with a shadow: `elevation.shadow.raised` (cards), `elevation.shadow.overlay` (modals, dropdowns), `elevation.shadow.overflow` (scroll edges). In dark mode surfaces get lighter instead of shadows getting stronger.

## Motion

- Durations: 100ms (small state changes), 200ms (dropdowns, flags), 350ms (modals, drawers) (approx.).
- Easing: ease-out for entering (`cubic-bezier(0.2, 0, 0, 1)` approx.), ease-in for leaving; no bounce.
- Flags slide in from the bottom-left; modals fade and scale slightly.
- `prefers-reduced-motion`: fades only.

## Components

- **Buttons**: appearances `primary` (one per area), `default`, `subtle`, `link`, `warning`, `danger`; height 32px (compact 24px); label sentence case.
- **Lozenges** for status (uppercase, bold appearance only for emphasis); **badges** for counts.
- **Forms**: label above field, helper text below, inline validation on blur; required marked with `*` and explained once.
- **Flags** (toasts) bottom-left for feedback; **section messages** inline for persistent information.
- **Tables** (dynamic table): sortable headers, row height 40px, empty state with illustration + one action.
- **Modals**: sizes small 400 / medium 600 / large 800 / x-large 968px; primary action on the right.
- **Empty / loading / error**: spinner or skeleton for content areas, empty states with one clear action.

## Accessibility

- Token text/background pairs meet 4.5:1; never put `color.text.subtlest` on sunken surfaces for essential text.
- Focus: 2px `color.border.focused` outline on every interactive element, visible on keyboard focus.
- Targets ≥ 24×24px (32px buttons by default).
- Status never by color alone: lozenges carry text, icons carry labels.
- All components from @atlaskit support keyboard and screen readers; keep their ARIA props.

## Rules for agents

- Use `@atlaskit/tokens` `token('color.text')` (or CSS `var(--ds-text)`); never write a hex value.
- Build with @atlaskit components (`@atlaskit/button`, `@atlaskit/textfield`, `@atlaskit/modal-dialog`, `@atlaskit/primitives` Box/Stack/Inline for layout with `space` tokens).
- Switch themes with `setGlobalTheme({ colorMode: 'auto' })`; test light and dark.
- Spacing only from `space.*` tokens; radius only from `border.radius.*`.
- Use the semantic status families for meaning; never pick a "nice" color.
- One primary button per region; destructive actions use `danger` and a confirmation.
