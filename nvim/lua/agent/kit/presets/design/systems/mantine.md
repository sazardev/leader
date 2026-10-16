<!-- name: Mantine -->
<!-- desc: Mantine v7/v8: theme object, 10-shade color tuples, CSS variables, rich React components and hooks -->

# DESIGN.md: Mantine

Mantine (React components and hooks). Source of truth: mantine.dev. The design is one `createTheme({...})` object passed to
`MantineProvider`; every value is exposed as a CSS variable (`--mantine-color-blue-6`, `--mantine-spacing-md`).

## Principles

- **One theme object**: colors, fonts, radius, spacing, breakpoints and component defaults live in `createTheme`.
- **CSS variables, no runtime CSS-in-JS** (v7+): styles are CSS modules and variables, fast and SSR friendly.
- **Light and dark built in**: `defaultColorScheme="auto"` and `light-dark()` values.
- **Batteries included**: forms, dates, notifications, modals, hooks; prefer them to new dependencies.

## Color

Each color is a tuple of 10 shades (0 lightest … 9 darkest); `primaryShade` (default 6 light / 8 dark) is the one components use.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `--mantine-color-blue-6` (primary) | `#228BE6` | `#1C7ED6` (shade 8) | Filled buttons, links |
| `--mantine-color-body` | `#FFFFFF` | `#242424` | App background |
| `--mantine-color-text` | `#000000` | `#C9C9C9` | Body text |
| `--mantine-color-dimmed` | `#868E96` | `#828282` | Secondary text |
| `--mantine-color-default-border` | `#DEE2E6` | `#424242` | Borders |
| `--mantine-color-default` | `#FFFFFF` | `#2E2E2E` | Default variant backgrounds |
| `--mantine-color-red-6` | `#FA5252` | `#E03131` (8) | Errors |
| `--mantine-color-green-6` | `#40C057` | `#2F9E44` (8) | Success |
| `--mantine-color-yellow-6` | `#FAB005` | `#F08C00` (8) | Warning |
| `--mantine-color-gray-0` | `#F8F9FA` | `#2E2E2E` | Subtle surfaces |

- Default palette: dark, gray, red, pink, grape, violet, indigo, blue, cyan, teal, green, lime, yellow, orange (10 shades each).
- A brand color = a new 10-shade tuple (generate with the Mantine colors generator) and `primaryColor: 'brand'`.

## Typography

Font: system stack by default (`fontFamily`), `fontFamilyMonospace`, `headings.fontFamily`.

| Token | Size / line height | Use |
| --- | --- | --- |
| `fontSizes.xs` | 12 / 1.4 | Captions |
| `fontSizes.sm` | 14 / 1.45 | UI text |
| `fontSizes.md` | 16 / 1.55 | Body (default) |
| `fontSizes.lg` | 18 / 1.6 | Lead |
| `fontSizes.xl` | 20 / 1.65 | Large text |
| `h1` | 34 / 1.3 | Page title |
| `h2` | 26 / 1.35 | Section |
| `h3` | 22 / 1.4 | Subsection |
| `h4` | 18 / 1.45 | Card title |

Headings weight 700 by default; set `headings.fontWeight` in the theme.

## Spacing and layout

- `spacing`: xs 10, sm 12, md 16, lg 20, xl 32px (rem based).
- Breakpoints: xs 36em, sm 48em, md 62em, lg 75em, xl 88em.
- Layout: `AppShell` (header, navbar, aside, footer), `Container` (sizes), `Grid`/`SimpleGrid`, `Stack`, `Group`, `Flex`.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| `radius.xs` | 2px | Badges |
| `radius.sm` | 4px | Default (`defaultRadius`) |
| `radius.md` | 8px | Cards, inputs |
| `radius.lg` | 16px | Modals |
| `radius.xl` | 32px | Pills |

Shadows `shadows.xs` … `shadows.xl` for Paper, Card, Popover, Modal; in dark mode borders carry more of the separation.

## Motion

- Transitions via `Transition` component: `fade`, `pop`, `scale`, `slide-*` with `duration` ~150–200ms (approx. defaults).
- Modals and popovers fade/pop; `useReducedMotion` and `respectReducedMotion` in the theme disable them.
- Loaders: `Loader` (oval, bars, dots), `Skeleton`.

## Components

- **Button** variants: `filled` (primary), `light`, `outline`, `subtle`, `default`, `gradient`; `color="red"` for destructive.
- **Forms**: `@mantine/form` `useForm` with validation; `TextInput`, `Select`, `Checkbox`, `DateInput` (`@mantine/dates`) with `label`, `description`, `error`.
- **Feedback**: `@mantine/notifications` for toasts, `Alert` for inline messages, `Badge` for status.
- **Overlays**: `Modal`, `Drawer`, `Popover`, `Menu`, `Tooltip`; `@mantine/modals` `openConfirmModal` for confirmations.
- **Data**: `Table` (with `Table.ScrollContainer`), Mantine React Table / data-table libraries for heavy grids.
- **Empty / loading / error**: `Skeleton`, `Loader`, `Alert` with retry.

## Accessibility

- Components ship keyboard support and ARIA; keep `label` props (use `aria-label` for icon-only `ActionIcon`).
- Check contrast of custom tuples (shade 6 on white often fails for yellow/lime text: use shade 8–9 for text).
- Focus ring: `focusRing: 'auto'` (keyboard only); never `'never'`.
- `respectReducedMotion: true`.

## Rules for agents

- Configure everything in one `theme.ts` with `createTheme` and wrap the app in `MantineProvider` (+ `ColorSchemeScript` in SSR).
- Import `@mantine/core/styles.css` (and package styles you use) once; style custom parts with CSS modules and `var(--mantine-…)` variables.
- Colors by name and shade (`color="blue"`, `c="dimmed"`), never hex in components.
- Use style props (`p="md"`, `gap="sm"`) and theme spacing; no magic pixel values.
- Forms with `@mantine/form`; dates with `@mantine/dates`; notifications with `@mantine/notifications`.
