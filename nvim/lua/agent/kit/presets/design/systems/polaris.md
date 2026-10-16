<!-- name: Shopify Polaris -->
<!-- desc: Shopify's admin system: Polaris tokens, Inter-like UI type, 4px space scale, commerce-dense components -->

# DESIGN.md: Shopify Polaris

Polaris is the design system of the Shopify admin. Source of truth: polaris.shopify.com. Values come from
`@shopify/polaris-tokens` as CSS custom properties (`--p-color-bg-surface`, `--p-space-400`); components from `@shopify/polaris`.

## Principles

- **Merchants first**: every screen helps a merchant finish a task; clarity beats delight.
- **Efficient**: dense information, predictable layouts, keyboard friendly.
- **Consistent**: the same pattern solves the same problem everywhere in the admin.
- **Tokens everywhere**: color, space, radius, shadow and motion are tokens, never literals.
- **Accessible and inclusive**: WCAG 2.1 AA, plain language.

## Color

| Token | Light | Use |
| --- | --- | --- |
| `--p-color-bg` | `#F1F1F1` | Page background |
| `--p-color-bg-surface` | `#FFFFFF` | Cards |
| `--p-color-bg-surface-secondary` | `#F7F7F7` | Nested areas |
| `--p-color-bg-surface-hover` | `#F7F7F7` | Hover on surfaces |
| `--p-color-bg-fill-brand` | `#303030` | Primary buttons |
| `--p-color-text` | `#303030` | Body text |
| `--p-color-text-secondary` | `#616161` | Secondary text |
| `--p-color-text-disabled` | `#B5B5B5` | Disabled |
| `--p-color-text-link` | `#005BD3` | Links |
| `--p-color-text-critical` | `#8E0B21` | Errors |
| `--p-color-bg-fill-critical` | `#C70A24` | Destructive buttons |
| `--p-color-bg-fill-success` | `#29845A` | Success badges |
| `--p-color-bg-fill-warning` | `#FFB800` | Warning badges |
| `--p-color-border` | `#E3E3E3` | Dividers |
| `--p-color-border-focus` | `#005BD3` | Focus rings |

- The admin is light-first; dark surfaces exist for specific contexts (`--p-color-bg-inverse` `#1A1A1A`). A full dark mode is not standard (approx. support): plan dark only if the product needs it.
- Tones: `info`, `success`, `warning`, `critical`, `caution`, `magic` (AI features) each with fill, surface and text tokens.

## Typography

Font: Inter (via `--p-font-family-sans`, system fallback); mono: `--p-font-family-mono`.

| Variant | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| `heading3xl` | 36 / 48 | 700 | Rare hero numbers |
| `heading2xl` | 30 / 40 | 700 | Page title (marketing) |
| `headingXl` | 24 / 32 | 700 | Large titles |
| `headingLg` | 20 / 24 | 650 | Page title (admin) |
| `headingMd` | 14 / 20 | 650 | Card title |
| `headingSm` | 13 / 20 | 650 | Section title |
| `bodyLg` | 14 / 20 | 450 | Emphasized body |
| `bodyMd` | 13 / 20 | 450 | Default body |
| `bodySm` | 12 / 16 | 450 | Help text |

Weights 450/650 are Inter variable weights (approx. elsewhere: 400/600). Numbers in tables use `numeric` (tabular).

## Spacing and layout

- 4px base: `--p-space-050` 2, `100` 4, `150` 6, `200` 8, `300` 12, `400` 16, `500` 20, `600` 24, `800` 32, `1000` 40, `1200` 48, `1600` 64.
- Page: `Page` component with max width 998px (default) or full width; `Layout` sections one-half/one-third/two-thirds.
- Breakpoints: xs 0, sm 490, md 768, lg 1040, xl 1440px.
- Card padding 16px (`400`) mobile, 20px desktop (approx.).

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| `--p-border-radius-100` | 4px | Small controls |
| `--p-border-radius-200` | 8px | Buttons, inputs |
| `--p-border-radius-300` | 12px | Cards |
| `--p-border-radius-400` | 16px | Modals |
| `--p-border-radius-full` | 9999px | Pills, avatars |

Shadows: `--p-shadow-100` (cards), `--p-shadow-200`… `--p-shadow-600` (popovers, modals); buttons use a subtle bevel shadow (`--p-shadow-button`).

## Motion

- Durations: `--p-motion-duration-100` 100ms, `150` 150ms, `200` 200ms, `250` 250ms, `300` 300ms, `500` 500ms.
- Easing: `--p-motion-ease` `cubic-bezier(0.25, 0.1, 0.25, 1)`, `--p-motion-ease-in`, `--p-motion-ease-out`, `--p-motion-ease-in-out`.
- Keyframes tokens for spin, appear, fade; motion is functional (feedback, orientation), never ornamental.
- `prefers-reduced-motion`: no movement, fades only.

## Components

- **Buttons**: `variant="primary"` (one per card/page), secondary (default), `tertiary`, `plain`; `tone="critical"` for destructive.
- **Cards** group related content; `BlockStack`/`InlineStack` with `gap` tokens for layout inside.
- **IndexTable / DataTable** for resources: bulk actions, filters, sticky header, pagination.
- **Forms**: `FormLayout`, `TextField` with label, help text, inline error; `ContextualSaveBar` for unsaved changes.
- **Feedback**: `Toast` for short confirmations, `Banner` for persistent messages, `Badge` for status.
- **Empty / loading / error**: `EmptyState` with illustration and one action; `SkeletonPage` while loading.

## Accessibility

- Text and fill tokens meet 4.5:1; never put `text-secondary` on `bg-fill` colors.
- Focus: visible 2px focus ring (`--p-color-border-focus`) on all controls.
- Labels on every field (visually hidden only with `labelHidden`, never removed).
- Keyboard: every action reachable; IndexTable supports keyboard selection.
- Status uses Badge text and tone, not color alone.

## Rules for agents

- Use `@shopify/polaris` components inside `AppProvider` with the i18n translations; do not restyle them with custom CSS.
- Layout with `Page`, `Layout`, `Card`, `BlockStack`, `InlineStack`, `Box` and space tokens; no custom margins.
- Raw CSS (rare) uses `var(--p-…)` tokens from `@shopify/polaris-tokens`; never hex values.
- One primary action per page in `Page primaryAction`; secondary actions in `secondaryActions`.
- Destructive actions: `tone="critical"` plus a confirmation `Modal`.
- Copy follows Polaris content guidelines: sentence case, verbs on buttons, no jargon.
