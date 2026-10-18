<!-- name: Material You -->
<!-- desc: dynamic color from wallpaper, rounded shapes, motion, personal and adaptive -->

# DESIGN.md: Material You

The look of Material You: a distinctive UI style. Source: design trend and product references; values are approximations.

## Principles

- Dynamic color: palette generated from user wallpaper or seed color.
- Rounded shapes: large corner radii and pill buttons.
- Motion: expressive, physics-based transitions.
- Personal: UI adapts to the user's color and density.
- Accessible: tonal palettes meet contrast in light/dark.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#FFFBFE` | `#FFFBFE` (approx.) | App background |
| `surface` | `#F3EDF7` | `#F3EDF7` (approx.) | Cards, panels |
| `text` | `#1C1B1F` | `#1C1B1F` (approx.) | Body text |
| `text-muted` | `#49454F` | `#49454F` (approx.) | Secondary text |
| `accent` | `#6750A4` | `#6750A4` | Primary actions, focus |
| `on-accent` | `#FFFFFF` | `#FFFFFF` | Text on accent |
| `success` | `#386A20` | `#386A20` | Success states |
| `danger` | `#B3261E` | `#B3261E` | Destructive actions |

- Accent is used for primary actions, links and focus; large surfaces stay neutral.

## Typography

Fonts: Roboto / Google Sans for UI, system mono for code (approx.)

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| Display | 32–48px / 1.1 | 600–700 | Hero headings (approx.) |
| Heading | 20–24px / 1.25 | 600 | Section titles (approx.) |
| Body | 16px / 1.5 | 400 | Long-form text (approx.) |
| UI | 14px / 1.4 | 400–500 | Controls, inputs (approx.) |
| Small | 12–13px / 1.4 | 400 | Metadata, hints (approx.) |

- Use consistent type scale and line height for readability.

## Spacing and layout

- 4px base; common steps 4, 8, 12, 16, 24, 32, 48 (approx.).
- Content centered with comfortable max width and side margins.
- Sidebar ~240px on desktop; collapses on narrow screens.
- Composer or primary action pinned where relevant.

## Shape and elevation

- Radius: 4–8px (buttons, inputs), 12px (cards), 16px (modals) (approx.).
- Borders: 1px, low contrast; surfaces separate by lightness steps.
- Elevation for floating layers only: soft shadow plus 1px border on menus, popovers, modals.

## Motion

| Token | Value |
| --- | --- |
| duration-fast | 100–150ms (approx.) |
| duration-default | 150–250ms (approx.) |
| easing | ease-out (approx.) |

- Hover and state changes are subtle; menus fade/slide quickly.
- Reduced motion: no slides, fades only.

## Components

- **Layout**: sidebar + main content, responsive collapse.
- **Cards**: surface background, border, hover elevation.
- **Buttons**: primary (accent), secondary (subtle), ghost.
- **Inputs**: labeled fields with helper text and validation.
- **Feedback**: toasts and inline notices; confirm destructive actions.
- **Empty states**: one sentence plus next action.

## Accessibility

- Text and `text-muted` meet 4.5:1 on their surfaces.
- Focus visible on every interactive element.
- Keyboard navigation covers primary flows.
- Color never alone for status; icons and labels accompany color.
- Targets ≥ 24px on desktop, 44px on touch.

## Rules for agents

- Implement tokens as CSS variables; components never hardcode colors.
- Support light and dark themes from the same tokens where applicable.
- Keep components consistent with the style's principles.
- Use the accent sparingly; keep surfaces neutral.
- Prefer subtle borders and lightness steps over shadows.
- Every new action is keyboard reachable.
