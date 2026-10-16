<!-- name: Corporate clean -->
<!-- desc: enterprise SaaS: neutral grays, trustworthy blue, accessible density, clear forms and predictable patterns -->

# DESIGN.md: Corporate clean

A neutral, trustworthy style for B2B and enterprise software: cool grays, one confident blue, clear forms, predictable
navigation and accessible density. Familiar on purpose: users learn it once and move fast.

## Principles

- **Predictable over novel**: standard patterns, placed where users expect them.
- **Trust through clarity**: plain labels, explicit states, no surprises on save or delete.
- **Accessible by default**: AA everywhere, AAA for body text where possible.
- **Comfortable density**: efficient without feeling cramped.
- **Consistent everywhere**: one component per job across the whole product.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#F5F7FA` | `#0F1419` | App background |
| `surface` | `#FFFFFF` | `#171D24` | Cards, panels, tables |
| `surface-subtle` | `#EEF2F6` | `#1E262F` | Headers, hovers |
| `border` | `#D5DCE4` | `#2E3843` | Borders, dividers |
| `text` | `#1B2430` | `#E8EDF2` | Text |
| `text-muted` | `#55606E` | `#9FAAB7` | Secondary |
| `primary` | `#0B5FFF` | `#4C8DFF` | Primary actions, links, selection |
| `primary-hover` | `#004BD6` | `#6EA2FF` | Hover |
| `on-primary` | `#FFFFFF` | `#0F1419` | Text on primary |
| `info` | `#0B5FFF` | `#4C8DFF` | Info |
| `success` | `#13795B` | `#3DD68C` | Success |
| `warning` | `#9A5B00` | `#F5B83D` | Warning |
| `danger` | `#C4271B` | `#FF7066` | Destructive, errors |

## Typography

Font: Inter or IBM Plex Sans, fallback `system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`.

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| h1 | 28 / 36 | 600 | Page titles |
| h2 | 20 / 28 | 600 | Sections |
| h3 | 16 / 24 | 600 | Card titles |
| body | 14 / 22 | 400 | Default |
| body-lg | 16 / 26 | 400 | Long text, onboarding |
| label | 13 / 18 | 500 | Form labels, column headers |
| caption | 12 / 16 | 400 | Help text |

## Spacing and layout

- 4px base; scale 4, 8, 12, 16, 24, 32, 40, 48, 64.
- Shell: top bar 56px, left navigation 240px (collapsible to 64px), content max 1440px with 24px padding.
- Forms in one column (max 640px), label above field; related fields grouped with section titles.
- Breakpoints: 640, 1024, 1280.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| `radius-sm` | 4px | Inputs, buttons, badges |
| `radius-md` | 8px | Cards, dialogs |
| `elevation-1` | `0 1px 2px rgb(16 24 40 / 0.06)` | Cards |
| `elevation-2` | `0 8px 24px rgb(16 24 40 / 0.12)` | Popovers, dialogs |

## Motion

| Token | Value |
| --- | --- |
| `duration-fast` | 100ms |
| `duration-base` | 200ms |
| `ease` | `cubic-bezier(0.2, 0, 0, 1)` |

- Functional only: dialogs fade/scale 0.98→1, drawers slide, toasts slide in. Reduced motion: fades only.

## Components

- **Buttons**: primary, secondary (border), tertiary (text), destructive (danger); 36px high; one primary per view.
- **Forms**: inputs 36px, required marked with text "(required)" or `*` explained once; inline validation on blur; error summary at the top of long forms.
- **Tables**: sortable, filterable, row actions in a kebab menu, bulk actions bar on selection.
- **Navigation**: left nav with sections, breadcrumb on detail pages, tabs for sub-views.
- **Dialogs**: title, body, actions right-aligned (primary last); destructive dialogs name the thing being deleted.
- **Toasts**: bottom-left, auto-dismiss 5s except errors.
- **States**: empty (illustration optional, explanation, primary action), loading (skeletons), error (banner with what happened and what to do), permission denied (explain who can grant it).

## Accessibility

- WCAG 2.2 AA: text ≥ 4.5:1, UI components ≥ 3:1, focus visible (2px `primary` + 2px offset).
- Every input has a visible label; errors linked with `aria-describedby`; required state announced.
- Full keyboard support: tab order follows layout, dialogs trap focus and restore it.
- Targets ≥ 24×24px (WCAG 2.2 minimum), 44px on touch layouts.

## Rules for agents

- Use the component library's primitives; never style a native control from scratch when a component exists.
- One primary button per view; destructive actions always confirm with the object's name.
- Copy is plain and specific: say what happened and what to do next.
- No new color, radius or shadow outside the tokens.
- Every page handles empty, loading, error and no-permission states.
