<!-- name: Figma -->
<!-- desc: design tool UI: dark canvas, purple accent, dense panels, crisp icons, precise -->

# DESIGN.md: Figma

The look of Figma: a dense, dark design-tool interface with a neutral canvas, purple accent, crisp icons and precise
alignment that keeps the work area central. Source: Figma's product UI (figma.com); values are from the product and marked
"(approx.)" where they vary between versions or themes.

## Principles

- **Canvas first**: the document is the focus; panels and toolbars frame it without competing.
- **Dense but clear**: lots of controls in small space, grouped and labeled, never cluttered.
- **Precision**: pixel-aligned icons, consistent spacing, and exact values in inputs.
- **Fast and fluid**: instant feedback, smooth pan/zoom, no blocking on common actions.
- **Collaborative**: presence, cursors and comments are visible but unobtrusive.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#FFFFFF` | `#1E1E1E` (approx.) | App / canvas background |
| `surface` | `#F5F5F5` (approx.) | `#2C2C2C` (approx.) | Panels, sidebars, toolbars |
| `surface-raised` | `#FFFFFF` (approx.) | `#383838` (approx.) | Menus, popovers, modals |
| `text` | `#000000` (approx.) | `#FFFFFF` (approx.) | Body text, headings |
| `text-muted` | `#6B6B6B` (approx.) | `#B3B3B3` (approx.) | Secondary text, labels |
| `text-faint` | `#9B9B9B` (approx.) | `#7A7A7A` (approx.) | Placeholders, hints |
| `border` | `#E6E6E6` (approx.) | `#3D3D3D` (approx.) | 1px separators |
| `accent` | `#A259FF` (approx.) | `#A259FF` (approx.) | Primary buttons, selection, focus |
| `on-accent` | `#FFFFFF` | `#FFFFFF` | Text on accent |
| `success` | `#0ACF83` (approx.) | `#0ACF83` (approx.) | Success states |
| `warning` | `#FFC700` (approx.) | `#FFC700` (approx.) | Warnings |
| `danger` | `#F24822` (approx.) | `#F24822` (approx.) | Destructive actions, errors |

- Accent is a Figma purple used for selection, primary actions and focus; large surfaces stay neutral.
- The canvas uses a subtle grid/checkerboard; panels use flat surfaces with 1px borders.

## Typography

Fonts: system sans-serif (approx. Inter / platform UI) for UI text, and a monospace for code and values (approx. system mono).
(approx.)

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| Heading | 14–16px / 1.3 | 600 | Panel and section titles (approx.) |
| Body | 13px / 1.4 | 400 | Labels and descriptions (approx.) |
| UI | 11–12px / 1.3 | 400–500 | Dense controls, inputs, tooltips (approx.) |
| Small | 10–11px / 1.3 | 400 | Hints, metadata (approx.) |
| Code | 12–13px / 1.4 | 400 | Code and values (approx.) |

- UI text is compact; labels are short and precise.
- Tabular figures for numeric inputs and measurements.

## Spacing and layout

- 4px base; common steps 4, 8, 12, 16 (approx.).
- Left toolbar ~48px, right properties panel ~240–280px, bottom layers panel resizable.
- Panels are dense with 4–8px gaps and 1px dividers.
- Canvas fills the remaining space with pan/zoom.

## Shape and elevation

- Radius: 2–4px (buttons, inputs), 6px (panels, menus), 8px (modals) (approx.).
- Borders: 1px, low contrast; surfaces separate by lightness steps and borders.
- Elevation for floating layers only: a soft shadow plus a 1px border on menus, popovers and modals.

## Motion

| Token | Value |
| --- | --- |
| duration-fast | 80–120ms (approx.) |
| duration-default | 120–200ms (approx.) |
| easing | ease-out (approx.) |

- Pan, zoom and selection are instant; menus fade in quickly.
- Hover and state changes are snappy; nothing animates longer than ~200ms.
- Reduced motion: no slides, fades only.

## Components

- **Toolbar**: icon buttons with tooltips, grouped by tool, with a selected state.
- **Layers panel**: nested tree with icons, visibility and lock toggles.
- **Properties panel**: grouped inputs with labels, steppers and color pickers.
- **Canvas**: infinite pan/zoom surface with a subtle grid and selection handles.
- **Menus and popovers**: dense, with icons, shortcuts and separators.
- **Color picker**: swatches, sliders and hex input.
- **Comments**: pins on canvas with threaded replies in a sidebar.

## Accessibility

- Text and `text-muted` meet 4.5:1 on their surfaces in both themes.
- Focus visible on every interactive element (accent ring) for keyboard users.
- Keyboard shortcuts cover all tools and navigation; discoverable in menus.
- Color never alone for status; icons and labels accompany color.
- Targets ≥ 24px on desktop, 44px on touch.

## Rules for agents

- Implement tokens as CSS variables; components never hardcode colors; support light and dark themes from the same tokens.
- Keep panels dense but grouped; use 1px borders and 4px spacing.
- Use crisp icons with tooltips and keyboard shortcuts.
- Use the accent sparingly (selection, primary actions, focus); keep surfaces neutral.
- Prefer subtle borders and lightness steps over shadows; floating layers are the only elevated surfaces.
- Every new action is keyboard reachable and shown in its tooltip/menu row.
