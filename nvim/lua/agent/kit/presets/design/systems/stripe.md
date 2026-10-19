<!-- name: Stripe -->
<!-- desc: clean payments UI: white surfaces, indigo accent, precise typography, trust and clarity -->

# DESIGN.md: Stripe

The look of Stripe: a clean, precise, trust-first payments interface with white surfaces, an indigo accent, generous
whitespace and careful typography. Source: Stripe's product UI and brand (stripe.com, dashboard.stripe.com); values are from
the product and marked "(approx.)" where they vary between versions or themes.

## Principles

- **Trust first**: clarity and correctness over decoration; every amount, status and action is unambiguous.
- **Precise**: aligned grids, consistent spacing, and tabular figures for money and IDs.
- **Calm**: white surfaces, soft grays and one accent; no visual noise around critical data.
- **Progressive disclosure**: advanced options (webhooks, metadata, raw payloads) are one click away.
- **Developer empathy**: code, IDs and payloads are first-class, copyable and well formatted.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#FFFFFF` | `#0A2540` (approx.) | App background |
| `surface` | `#FFFFFF` | `#1A365D` (approx.) | Cards, panels, modals |
| `surface-muted` | `#F6F9FC` (approx.) | `#0F2A4A` (approx.) | Sidebars, secondary panels |
| `text` | `#0A2540` (approx.) | `#FFFFFF` | Body text, headings |
| `text-muted` | `#425466` (approx.) | `#A3B1C6` (approx.) | Secondary text, metadata |
| `text-faint` | `#8898AA` (approx.) | `#6B7C93` (approx.) | Placeholders, hints |
| `border` | `#E3E8EE` (approx.) | `#2A4A7F` (approx.) | 1px separators |
| `accent` | `#635BFF` | `#635BFF` | Primary buttons, links, focus |
| `on-accent` | `#FFFFFF` | `#FFFFFF` | Text on accent |
| `success` | `#00D4AA` (approx.) | `#00D4AA` (approx.) | Success states |
| `warning` | `#FFC107` (approx.) | `#FFC107` (approx.) | Warnings |
| `danger` | `#DF1B41` (approx.) | `#DF1B41` (approx.) | Destructive actions, errors |

- Accent is a Stripe purple/indigo used for primary actions, links and focus; large surfaces stay white or navy.
- Money and status use color plus text and icons, never color alone.

## Typography

Fonts: system sans-serif (approx. Stripe's custom / Inter / platform UI) for UI text, and a monospace for IDs, code and
payloads (approx. system mono). (approx.)

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| Display | 32–48px / 1.1 | 600 | Marketing and empty-state headings (approx.) |
| Heading | 20–24px / 1.25 | 600 | Section and panel titles (approx.) |
| Body | 16px / 1.5 | 400 | Descriptions and long-form text (approx.) |
| UI | 14px / 1.4 | 400–500 | Table rows, buttons, inputs (approx.) |
| Small | 12–13px / 1.4 | 400 | Metadata, IDs, hints (approx.) |
| Code | 13–14px / 1.5 | 400 | Code blocks, payloads, IDs (approx.) |

- Headings use tight tracking at large sizes; body text uses default tracking.
- Tabular figures and monospace for amounts, IDs and timestamps.

## Spacing and layout

- 4px base; common steps 4, 8, 12, 16, 24, 32, 48 (approx.).
- Dashboard uses a sidebar (~240px) plus a main content area with generous padding.
- Tables are dense but readable, with fixed column widths for amounts and statuses.
- Forms use a single column with clear labels and helper text.

## Shape and elevation

- Radius: 4–6px (buttons, inputs), 8px (cards), 12px (modals, popovers) (approx.).
- Borders: 1px, low contrast; surfaces separate mostly by lightness steps and subtle borders.
- Elevation for floating layers only: a soft large shadow plus a 1px border on menus, popovers and modals.

## Motion

| Token | Value |
| --- | --- |
| duration-fast | 100–150ms (approx.) |
| duration-default | 150–250ms (approx.) |
| easing | ease-out (approx.) |

- Hover and state changes are subtle; menus fade/slide in quickly; nothing animates longer than ~300ms.
- Loading uses skeletons and spinners; optimistic updates where safe.
- Reduced motion: no slides, fades only.

## Components

- **Dashboard**: sidebar navigation, search, and a main content area with cards, tables and charts.
- **Tables**: dense rows with status badges, amounts in tabular figures, and row actions on hover.
- **Forms**: labeled fields, helper text, inline validation, and clear primary/secondary actions.
- **Code blocks**: surface background, language label, and copy button; horizontal scroll for wide payloads.
- **Buttons**: primary (accent fill), secondary (subtle surface + border), ghost for most actions.
- **Feedback**: toasts and inline notices; destructive actions use a confirm dialog.
- **Empty states**: one sentence plus the next action; no marketing chrome inside the app.

## Accessibility

- Text and `text-muted` meet 4.5:1 on their surfaces in both themes.
- Focus visible on every interactive element (accent ring) for keyboard users.
- Keyboard navigation covers search, tables and forms; shortcuts are discoverable.
- Color never alone for status; icons and labels accompany color.
- Targets ≥ 24px on desktop, 44px on touch.

## Rules for agents

- Implement tokens as CSS variables; components never hardcode colors; support light and dark themes from the same tokens.
- Use tabular figures and monospace for money, IDs and timestamps; align columns consistently.
- Keep forms single-column with clear labels and helper text; validate inline.
- Use the accent sparingly (primary actions, focus, links); keep surfaces clean and low-contrast.
- Prefer subtle borders and lightness steps over shadows; floating layers are the only elevated surfaces.
- Every new action is keyboard reachable and shown in its tooltip/menu row.
