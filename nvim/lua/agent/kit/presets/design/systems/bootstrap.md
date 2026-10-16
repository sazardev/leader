<!-- name: Bootstrap 5 -->
<!-- desc: Bootstrap 5.3: CSS variables, color modes, 12-column grid, utilities and Sass maps -->

# DESIGN.md: Bootstrap 5

Bootstrap 5.3. Source of truth: getbootstrap.com. Values come from Sass variables and maps compiled into CSS custom
properties (`--bs-primary`, `--bs-body-bg`); light and dark are color modes (`data-bs-theme="dark"`).

## Principles

- **Utility + components**: compose with utilities (`d-flex`, `gap-3`, `p-4`), reach for components for behaviour.
- **Customize through Sass/variables**, never by overriding compiled CSS.
- **Mobile first**: base styles for small screens, breakpoints add.
- **Accessible components**: keyboard and ARIA patterns come with the JavaScript plugins.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `--bs-primary` | `#0D6EFD` | `#0D6EFD` | Primary actions, links |
| `--bs-secondary` | `#6C757D` | `#6C757D` | Secondary actions |
| `--bs-success` | `#198754` | `#198754` | Success |
| `--bs-danger` | `#DC3545` | `#DC3545` | Errors, destructive |
| `--bs-warning` | `#FFC107` | `#FFC107` | Warning |
| `--bs-info` | `#0DCAF0` | `#0DCAF0` | Info |
| `--bs-body-bg` | `#FFFFFF` | `#212529` | App background |
| `--bs-body-color` | `#212529` | `#DEE2E6` | Body text |
| `--bs-secondary-color` | `rgba(33,37,41,.75)` | `rgba(222,226,230,.75)` | Secondary text |
| `--bs-tertiary-bg` | `#F8F9FA` | `#2B3035` | Subtle surfaces |
| `--bs-border-color` | `#DEE2E6` | `#495057` | Borders |
| `--bs-link-color` | `#0D6EFD` | `#6EA8FE` | Links |
| `--bs-primary-text-emphasis` | `#052C65` | `#6EA8FE` | Text on subtle primary |
| `--bs-primary-bg-subtle` | `#CFE2FF` | `#031633` | Subtle primary backgrounds |

- Each theme color has `-text-emphasis`, `-bg-subtle` and `-border-subtle` variants for both modes.
- Change the brand with `$primary` in Sass (or `--bs-primary` + `--bs-primary-rgb`).

## Typography

Font: native system stack (`$font-family-sans-serif`), monospace `$font-family-monospace`; base 1rem (16px), line height 1.5.

| Class | Size | Weight | Use |
| --- | --- | --- | --- |
| `h1` | 2.5rem (40px), responsive | 500 | Page title |
| `h2` | 2rem (32px) | 500 | Section |
| `h3` | 1.75rem (28px) | 500 | Subsection |
| `h4` | 1.5rem (24px) | 500 | Card title |
| `h5` | 1.25rem (20px) | 500 | Small heading |
| `h6` | 1rem (16px) | 500 | Label heading |
| `display-1` … `display-6` | 5rem … 2.5rem | 300 | Hero |
| `lead` | 1.25rem | 300 | Intro paragraph |
| `small` | 0.875em | 400 | Metadata |

Headings use RFS (responsive font sizes) above the `lg` breakpoint.

## Spacing and layout

- Spacer scale (`$spacer: 1rem`): 0 → 0, 1 → .25rem, 2 → .5rem, 3 → 1rem, 4 → 1.5rem, 5 → 3rem (`m-*`, `p-*`, `gap-*`).
- Breakpoints: xs < 576, sm ≥ 576, md ≥ 768, lg ≥ 992, xl ≥ 1200, xxl ≥ 1400px.
- Containers: 540, 720, 960, 1140, 1320px; 12-column grid with 1.5rem gutters (`g-*` to change).

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| `--bs-border-radius-sm` | .25rem | Small controls |
| `--bs-border-radius` | .375rem | Buttons, inputs, cards |
| `--bs-border-radius-lg` | .5rem | Large controls, modals |
| `--bs-border-radius-xl` | 1rem | Large cards |
| `--bs-border-radius-pill` | 50rem | Pills |
| `--bs-border-width` | 1px | Borders |

Shadows: `shadow-sm` `0 .125rem .25rem rgba(0,0,0,.075)`, `shadow` `0 .5rem 1rem rgba(0,0,0,.15)`, `shadow-lg` `0 1rem 3rem rgba(0,0,0,.175)`.

## Motion

- Transitions: buttons/inputs `.15s ease-in-out`; collapse `.35s ease`; modal fade `.15s linear` + slide `.3s ease-out`.
- Carousel slides `.6s ease-in-out`.
- `$enable-reduced-motion: true` disables transitions under `prefers-reduced-motion`.

## Components

- **Buttons**: `btn-primary` (one per area), `btn-outline-*`, `btn-link`; `btn-danger` for destructive; sizes `btn-sm`/`btn-lg`.
- **Forms**: `form-label` + `form-control`/`form-select`, `form-text` help, validation with `is-invalid` + `invalid-feedback`; floating labels optional.
- **Navigation**: `navbar` (collapses below `lg`), `nav-tabs`, `breadcrumb`, `pagination`.
- **Feedback**: `alert`, `toast`, `badge`, `spinner-border`, `placeholder` (skeletons).
- **Overlays**: `modal` (footer: Cancel then primary), `offcanvas`, `dropdown`, `tooltip`/`popover` (require Popper).
- **Tables**: `table`, `table-hover`, `table-responsive` wrapper for small screens.

## Accessibility

- Theme colors on white: check text contrast (`warning`/`info` text needs `-text-emphasis`).
- Focus ring: `.25rem` `rgba(var(--bs-primary-rgb), .25)` box-shadow (`$focus-ring-*`); never remove it.
- Use the JS plugins' markup as documented (ARIA attributes, `visually-hidden` labels).
- Color modes: test `data-bs-theme="dark"`.

## Rules for agents

- Customize in `scss/_variables.scss` overrides before importing Bootstrap (`$primary`, `$border-radius`, `$font-family-sans-serif`); or CSS variables for runtime theming.
- Prefer utilities for spacing/layout (`d-flex gap-3`, `p-4`, `col-md-6`); write custom CSS only for what utilities cannot express, reading `var(--bs-…)`.
- Use `data-bs-theme` for dark mode; never hardcode light colors.
- Load only the JS plugins you use (ES modules) and Popper for dropdowns/tooltips.
- Destructive actions: `btn-danger` + a confirmation `modal`.
