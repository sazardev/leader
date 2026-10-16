<!-- name: Linear -->
<!-- desc: dark-first dense product UI: LCH-generated themes, Inter, 13px UI text, keyboard-first, fast motion -->

# DESIGN.md: Linear

The look of Linear: a fast, dense, keyboard-first product tool, dark by default, with themes generated in LCH color space
from three variables (base, accent, contrast). Source: Linear's product UI and its published write-ups on the redesign
(linear.app/now). There is no public token set: values are from the product and marked "(approx.)".

## Principles

- **Speed is a feature**: every interaction feels instant (optimistic updates, local-first data, short motion).
- **Keyboard first**: every action has a shortcut and is reachable from the command menu (`Cmd/Ctrl+K`).
- **Quiet chrome, sharp content**: low-contrast surfaces and subtle borders; the issue titles and statuses carry the contrast.
- **Density with order**: lots of information per row, aligned on a strict grid, never cluttered.
- **Opinionated defaults**: fewer settings, well-chosen behaviour.

## Color

Themes are generated in **LCH** from `base` (background hue/lightness), `accent` and `contrast`; the generator produces the surface, text and border steps with perceptually even spacing.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#FFFFFF` (approx.) | `#08090A` (approx.) | App background |
| `surface` | `#F7F8F8` (approx.) | `#0F1011` (approx.) | Sidebar, panels |
| `surface-raised` | `#FFFFFF` (approx.) | `#1C1D1F` (approx.) | Menus, popovers, modals |
| `text` | `#0A0A0B` (approx.) | `#F7F8F8` (approx.) | Titles, main text |
| `text-muted` | `#6B6F76` (approx.) | `#8A8F98` (approx.) | Secondary text, metadata |
| `border` | `rgba(0,0,0,0.08)` (approx.) | `rgba(255,255,255,0.08)` (approx.) | 1px separators |
| `primary` (accent) | `#5E6AD2` | `#5E6AD2` | Primary buttons, focus, selection |
| `on-primary` | `#FFFFFF` | `#FFFFFF` | Text on accent |
| `success` | `#4CB782` (approx.) | `#4CB782` (approx.) | Done status |
| `warning` | `#F2C94C` (approx.) | `#F2C94C` (approx.) | In-progress / attention |
| `danger` | `#EB5757` (approx.) | `#EB5757` (approx.) | Urgent priority, destructive |
| `focus` | `#5E6AD2` | `#5E6AD2` | Focus rings |

- Status and priority have fixed colored icons (circle fills, bars); color reinforces the icon, never replaces it.
- Custom themes: the user picks base, accent and contrast; components only read the generated tokens.

## Typography

Font: Inter (Inter Display for large headings), with the system UI stack as fallback; Berkeley Mono / system mono for IDs and code (approx.).

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| Display | 32–48px / 1.1 | 600 | Marketing and empty-state headings (approx.) |
| Title | 20px / 28px | 600 | Issue title in detail view (approx.) |
| Heading | 15px / 22px | 500 | Section headers (approx.) |
| Body | 14px / 20px | 400 | Descriptions, comments (approx.) |
| UI | 13px / 18px | 400–500 | List rows, sidebar, buttons (approx.) |
| Small | 12px / 16px | 400–500 | Meta, badges, shortcuts (approx.) |

- Tabular figures for counts and IDs; issue IDs (`ENG-123`) in muted mono-like style.
- Tight but readable letter spacing on large headings (slightly negative), default on UI text.

## Spacing and layout

- 4px base; common steps 4, 8, 12, 16, 24, 32 (approx.).
- List rows ~36px high (approx.); sidebar ~220–240px; detail view opens as a side panel or full page.
- Layout: sidebar (workspace, teams, views) + main list/board + optional detail panel; everything resizable, nothing floating without reason.
- Grouping and filtering live in the view header, not in separate pages.

## Shape and elevation

- Radius: 4px (badges, small controls), 6px (buttons, inputs), 8–12px (menus, modals, cards) (approx.).
- Borders: 1px, very low contrast (`border`); in dark mode surfaces separate by lightness steps and borders, not shadows.
- Elevation for floating layers only: a soft large shadow plus a 1px border on menus, popovers, command menu and modals.

## Motion

| Token | Value |
| --- | --- |
| duration-fast | 100–150ms (approx.) |
| duration-default | 150–200ms (approx.) |
| easing | `cubic-bezier(0.25, 0.46, 0.45, 0.94)` / ease-out (approx.) |

- Hover and state changes are almost instant; menus and panels fade/slide in quickly; nothing animates longer than ~250ms.
- Optimistic UI: the change shows immediately, sync happens in the background, errors roll back with a toast.
- Reduced motion: no slides, fades only.

## Components

- **Command menu** (`Cmd/Ctrl+K`): fuzzy search over every action, with the shortcut shown on the right; contextual to the selection.
- **Lists**: dense rows with priority icon, ID, title, labels, assignee avatar, status icon; multi-select with `x`/Shift, bulk actions in a bottom bar.
- **Boards**: columns by status, compact cards with the same metadata as rows.
- **Buttons**: primary (accent fill) rare; secondary (subtle surface + border) and ghost buttons for most actions; every button can show its shortcut in a tooltip.
- **Inputs**: borderless or subtle-border fields, inline editing of properties via small popover pickers (status, priority, assignee, labels) with search.
- **Feedback**: toasts at the bottom with undo; empty states with one sentence and the shortcut to create.
- **Peek/detail**: Space previews an issue, Enter opens it; Esc always goes back.

## Accessibility

- Text and `text-muted` meet 4.5:1 on their surfaces in both themes; check generated custom themes with the contrast variable.
- Focus visible on every element (accent ring, 2px) for keyboard users; keyboard navigation is the primary path, not an afterthought.
- Icons for status/priority have accessible names; color never alone.
- Hover-only actions also appear on focus and in the command menu.
- Targets ≥ 24px on desktop, 44px on touch/mobile.

## Rules for agents

- Implement tokens as CSS variables generated from `base`, `accent` and `contrast` (an LCH/OKLCH theme function); components never hardcode colors.
- Every new action gets a shortcut and a command menu entry; show the shortcut in its tooltip/menu row.
- Mutations are optimistic: update local state first, reconcile with the server, roll back with a toast on failure.
- Keep motion under 200ms and use fades/short slides; never block input on an animation.
- Keep rows dense and aligned (fixed column widths for icons, IDs, avatars); no card-heavy layouts for list data.
- Dark theme is the default reference; check every screen in light too.
