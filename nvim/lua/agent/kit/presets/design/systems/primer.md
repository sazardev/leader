<!-- name: Primer -->
<!-- desc: GitHub's system: functional color tokens, system fonts, 14px base, 4px spacing, 6px radius, dense UI -->

# DESIGN.md: Primer

Primer, GitHub's design system. Source of truth: primer.style (Primer Primitives for tokens, Primer React, Primer CSS and
Primer ViewComponents for Rails). Colors are **functional tokens** (`fgColor-default`, `bgColor-muted`, `borderColor-default`)
mapped per theme (light, dark, dimmed, high contrast, colorblind); components never use base scales (`blue-5`) directly.

## Principles

- **Content first**: code, issues and text are the product; the UI is quiet and dense around them.
- **Functional color**: color means something (accent, success, attention, danger, done, sponsors); decoration is avoided.
- **Consistent and predictable**: the same patterns for the same jobs across every page.
- **Accessible to everyone**: many themes (high contrast, colorblind) come for free when tokens are used.
- **Progressive**: works without JavaScript where possible, enhanced with it.

## Color

Light and dark default themes (Primer Primitives v8+ names; older names in parentheses).

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `bgColor-default` (`canvas.default`) | `#FFFFFF` | `#0D1117` | Page background |
| `bgColor-muted` (`canvas.subtle`) | `#F6F8FA` | `#151B23` | Headers, sidebars, code |
| `bgColor-inset` | `#F6F8FA` | `#010409` | Inset areas |
| `fgColor-default` | `#1F2328` | `#F0F6FC` | Primary text |
| `fgColor-muted` | `#59636E` | `#9198A1` | Secondary text, icons |
| `borderColor-default` | `#D1D9E0` | `#3D444D` | Borders, dividers |
| `borderColor-muted` | `#D1D9E0B3` | `#3D444DB3` | Subtle dividers |
| `fgColor-accent` | `#0969DA` | `#4493F8` | Links, selected |
| `bgColor-success-emphasis` | `#1F883D` | `#238636` | Primary button |
| `fgColor-success` | `#1A7F37` | `#3FB950` | Success text/icons |
| `fgColor-attention` | `#9A6700` | `#D29922` | Warnings |
| `fgColor-danger` | `#D1242F` | `#F85149` | Errors, destructive |
| `fgColor-done` | `#8250DF` | `#AB7DF8` | Merged, done |
| `fgColor-onEmphasis` | `#FFFFFF` | `#FFFFFF` | Text on emphasis backgrounds |
| `focus-outlineColor` | `#0969DA` | `#1F6FEB` | Focus outline |

- Each role has `fgColor-*`, `bgColor-*-muted` (tinted) and `bgColor-*-emphasis` (solid), plus `borderColor-*-muted/emphasis`; use them as sets.
- Dark values are approx. for the newest primitives release; read them from `@primer/primitives` instead of copying.

## Typography

- System font stack: `-apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji"`; mono: `ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace`.
- Base size 14px, line height 1.5 (21px). Weights: 400 normal, 500 medium (approx. usage), 600 semibold (titles, buttons).

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| display | 40 / 1.4 | 500 | Marketing heroes only |
| title-large | 32 / 1.5 | 600 | Page titles |
| title-medium | 20 / 1.6 | 600 | Section titles, dialogs |
| title-small | 16 / 1.5 | 600 | Box headers, card titles |
| subtitle | 20 / 1.6 | 400 | Lead text |
| body-large | 16 / 1.5 | 400 | Reading text (markdown) |
| body-medium | 14 / 1.5 | 400 | Default UI text |
| body-small | 12 / 1.66 | 400 | Meta, counters |
| caption | 12 / 1.33 | 400 | Captions, labels |
| code-block | 13 / 1.5 | 400 | Code blocks |

## Spacing and layout

- 4px base, spacer scale: 0, 4, 8, 16, 24, 32, 40, 48 (`base-size-4` … `base-size-48`; utilities `p-1`…`p-6`).
- Page layout via `PageLayout` (header, pane, content, footer); content max width 1280px; pane 256–296px.
- Breakpoints: `sm` 544, `md` 768, `lg` 1012, `xl` 1280, `xxl` 1400 (px).
- Control sizes: small 28px, medium 32px (default), large 40px.

## Shape and elevation

- Radius: `borderRadius-small` 3px, `borderRadius-medium` 6px (default for buttons, inputs, boxes), `borderRadius-large` 12px (dialogs, overlays), `borderRadius-full` for avatars, labels and counters.
- Borders separate everything (1px `borderColor-default`); `Box` with border + radius 6 is the basic container.
- Shadows are small and only for floating UI: `shadow-resting-small` (buttons), `shadow-floating-small` (menus, popovers), `shadow-floating-large` (dialogs).

## Motion

- Minimal motion: functional transitions only (hover color, overlay open/close).
- Durations: 80–100ms for hover/color, 200ms for overlays, 300ms max (approx.; Primer has few motion tokens).
- Easing: `cubic-bezier(0.33, 1, 0.68, 1)` (ease-out) for entering overlays, `cubic-bezier(0.32, 0, 0.67, 0)` (ease-in) for leaving (approx.).
- Never animate content layout; respect `prefers-reduced-motion` (Primer components already do).

## Components

- **Buttons** variants: `primary` (green, one per view), `default`, `invisible`, `danger`; sizes small/medium/large; `IconButton` always with `aria-label`.
- **Forms**: `FormControl` with `FormControl.Label`, `Caption` and `Validation`; `TextInput`, `Select`, `Checkbox`, `Radio`, `Autocomplete`; validation message under the field.
- **Lists**: `ActionList` for menus and selectable lists, `NavList` for sidebars, `Timeline` for activity, `Box` rows for tabular data.
- **Navigation**: `UnderlineNav` for repo-like sections, `SegmentedControl` for view toggles, `Breadcrumbs`, `Pagination`.
- **Overlays**: `Dialog` for focused tasks, `ActionMenu` for menus, `Tooltip` for icon labels only, `SelectPanel` for filtered multi-select.
- **Feedback**: `Flash`/`Banner` (info, success, warning, critical), `Label`/`StateLabel` for status, `Spinner`/`SkeletonBox` for loading, `Blankslate` for empty states.

## Accessibility

- WCAG 2.1 AA minimum; text contrast ≥ 4.5:1, enforced by the token pairs; high contrast and colorblind themes must keep working.
- Focus: 2px solid `focus-outlineColor` outline with offset, on `:focus-visible`.
- Keyboard: composite widgets use roving focus (`ActionList`, `UnderlineNav`); overlays trap and return focus.
- Status is never color only: `StateLabel` has icon + text; diffs use symbols (+/−) besides color.
- Targets ≥ 24×24px (WCAG 2.2); 32px controls by default, larger on touch.

## Rules for agents

- React: `@primer/react` wrapped in `ThemeProvider` + `BaseStyles`; Rails: `primer_view_components`; plain HTML/CSS: `@primer/css`. Tokens from `@primer/primitives` CSS variables (`var(--fgColor-default)`).
- Never use base color scales or hex in components; use functional tokens (`fgColor-*`, `bgColor-*`, `borderColor-*`).
- Spacing and sizes from the scale (`var(--base-size-8)`, `var(--control-medium-size)`); radius `var(--borderRadius-medium)`.
- Prefer Primer components and patterns (Blankslate, PageLayout, ActionMenu) over custom ones; custom UI copies their structure.
- One `primary` button per view; destructive actions confirm in a `Dialog` with a `danger` button.
- Test every screen in light, dark and a high-contrast theme.
- Octicons (`@primer/octicons-react`) at 16px (default) or 24px; no other icon set.
