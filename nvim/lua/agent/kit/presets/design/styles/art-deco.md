<!-- name: Art Deco -->
<!-- desc: geometric elegance, gold accents, symmetry, luxurious and ornate -->

# DESIGN.md: Art Deco

The look of Art Deco: a distinctive UI style. Source: design trend and product references; values are approximations.

## Principles

- Geometric elegance: stepped forms, sunbursts, chevrons.
- Gold accents: metallic gold on dark, luxurious surfaces.
- Symmetry: balanced, centered compositions.
- Ornate: decorative borders and patterns.
- Luxury: rich materials and high contrast.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#1A1A2E` | `#1A1A2E` (approx.) | App background |
| `surface` | `#2D2D44` | `#2D2D44` (approx.) | Cards, panels |
| `text` | `#F5F0E6` | `#F5F0E6` (approx.) | Body text |
| `text-muted` | `#C4B89A` | `#C4B89A` (approx.) | Secondary text |
| `accent` | `#D4AF37` | `#D4AF37` | Primary actions, focus |
| `on-accent` | `#FFFFFF` | `#FFFFFF` | Text on accent |
| `success` | `#2E8B57` | `#2E8B57` | Success states |
| `danger` | `#8B0000` | `#8B0000` | Destructive actions |

- Accent is used for primary actions, links and focus; large surfaces stay neutral.

## Typography

Fonts: Playfair Display / Cinzel for display, Inter for body (approx.)

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
