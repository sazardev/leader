<!-- name: Fluent 2 -->
<!-- desc: Microsoft's system: Segoe UI Variable, brand ramp #0F6CBD, 4px spacing, layered shadows, quick easing -->

# DESIGN.md: Fluent 2

Fluent 2, Microsoft's design system for Windows, Microsoft 365 and the web. Source of truth: fluent2.microsoft.design and
the Fluent UI React v9 token reference (react.fluentui.dev). Every value is a **design token** (alias tokens such as
`colorNeutralForeground1` mapped onto global ramps); components read alias tokens, never ramps or hex values.

## Principles

- **Natural on every device**: adapts to the platform (Windows, web, iOS, Android) instead of forcing one look.
- **Built for focus**: calm neutral surfaces, brand color only where it guides action.
- **One for all, all for one**: accessible and inclusive by default (contrast, high contrast mode, keyboard, screen readers).
- **Unmistakably Microsoft**: brand ramp, Segoe UI Variable, soft depth with layered shadows.
- **Tokens over values**: alias tokens carry meaning (`Foreground1`, `Stroke2`, `Background3`) so light, dark and high contrast come from the theme.

## Color

Web light (`webLightTheme`) and dark (`webDarkTheme`) values. Brand ramp: brand 80 = `#0F6CBD` (light), brand 100 = `#479EF5` (dark).

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `colorNeutralBackground1` | `#FFFFFF` | `#292929` | Cards, main surface |
| `colorNeutralBackground2` | `#FAFAFA` | `#1F1F1F` | Secondary surface |
| `colorNeutralBackground3` | `#F5F5F5` | `#141414` | App/canvas background |
| `colorNeutralForeground1` | `#242424` | `#FFFFFF` | Primary text |
| `colorNeutralForeground2` | `#424242` | `#D6D6D6` | Secondary text |
| `colorNeutralForeground3` | `#616161` | `#ADADAD` | Tertiary text, placeholders |
| `colorNeutralStroke1` | `#D1D1D1` | `#666666` | Control borders |
| `colorNeutralStroke2` | `#E0E0E0` | `#525252` | Dividers, card borders |
| `colorBrandBackground` | `#0F6CBD` | `#115EA3` | Primary button |
| `colorBrandBackgroundHover` | `#115EA3` | `#0F6CBD` | Primary button hover |
| `colorNeutralForegroundOnBrand` | `#FFFFFF` | `#FFFFFF` | Text on brand |
| `colorBrandForeground1` | `#0F6CBD` | `#479EF5` | Links, selected text |
| `colorStatusSuccessForeground1` | `#0E700E` | `#54B054` | Success |
| `colorStatusWarningForeground1` | `#BC4B09` | `#FAA06B` | Warning |
| `colorStatusDangerForeground1` | `#B10E1C` | `#DC626D` | Error |
| `colorStrokeFocus2` | `#000000` | `#FFFFFF` | Focus ring |

- Status colors also have `Background1` (tinted) and `Border1` tokens; use the trio together in message bars and badges (approx. values; read them from the theme).
- High contrast is a third theme (`teamsHighContrastTheme` / Windows forced colors): never rely on shadows or tints alone.

## Typography

Font: `"Segoe UI Variable", "Segoe UI", -apple-system, BlinkMacSystemFont, Roboto, "Helvetica Neue", sans-serif`. Weights: regular 400, semibold 600, bold 700.

| Role (`typographyStyles`) | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| caption2 | 10 / 14 | 400 | Tiny metadata |
| caption1 | 12 / 16 | 400 | Captions, helper text |
| body1 | 14 / 20 | 400 | Default text |
| body1Strong | 14 / 20 | 600 | Emphasis in text, labels |
| body2 | 16 / 22 | 400 | Larger reading text |
| subtitle2 | 16 / 22 | 600 | Card titles |
| subtitle1 | 20 / 28 | 600 | Section titles |
| title3 | 24 / 32 | 600 | Page sub-titles |
| title2 | 28 / 36 | 600 | Page titles |
| title1 | 32 / 40 | 600 | Large page titles |
| largeTitle | 40 / 52 | 600 | Hero |
| display | 68 / 92 | 600 | Marketing, splash |

## Spacing and layout

- 4px base. Horizontal/vertical spacing tokens: `None` 0, `XXS` 2, `XS` 4, `SNudge` 6, `S` 8, `MNudge` 10, `M` 12, `L` 16, `XL` 20, `XXL` 24, `XXXL` 32.
- Layout on an 8px rhythm; component internals may use the nudge values.
- Breakpoints (approx., web): small < 640, medium 640–1023, large 1024–1365, x-large 1366–1919, xx-large ≥ 1920.
- Control heights: small 24, medium 32 (default), large 40.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| `borderRadiusNone` | 0 | Full-bleed surfaces |
| `borderRadiusSmall` | 2px | Badges, small chips |
| `borderRadiusMedium` | 4px | Buttons, inputs (default) |
| `borderRadiusLarge` | 6px | Cards (approx. usage) |
| `borderRadiusXLarge` | 8px | Dialogs, large surfaces |
| `borderRadiusCircular` | 10000px | Avatars, pills |

- Shadows: `shadow2`, `shadow4`, `shadow8`, `shadow16`, `shadow28`, `shadow64`, each two layers (ambient + key). Use 2–4 for cards and controls, 8–16 for flyouts/menus/tooltips, 28 for teaching popovers, 64 for dialogs. Brand variants `shadow*Brand` exist.
- Strokes: `strokeWidthThin` 1px (default), `Thick` 2px (focus, selected), `Thicker` 3px, `Thickest` 4px.

## Motion

| Token | Value |
| --- | --- |
| `durationUltraFast` | 50ms |
| `durationFaster` | 100ms |
| `durationFast` | 150ms |
| `durationNormal` | 200ms |
| `durationGentle` | 250ms |
| `durationSlow` | 300ms |
| `durationSlower` | 400ms |
| `durationUltraSlow` | 500ms |
| `curveAccelerateMax` | `cubic-bezier(0.9, 0.1, 1, 0.2)` |
| `curveAccelerateMid` | `cubic-bezier(1, 0, 1, 1)` |
| `curveDecelerateMax` | `cubic-bezier(0.1, 0.9, 0.2, 1)` |
| `curveDecelerateMid` | `cubic-bezier(0, 0, 0, 1)` |
| `curveEasyEase` | `cubic-bezier(0.33, 0, 0.67, 1)` |
| `curveEasyEaseMax` | `cubic-bezier(0.8, 0, 0.2, 1)` |
| `curveLinear` | `cubic-bezier(0, 0, 1, 1)` |

- Enter with decelerate curves, exit with accelerate curves; hover/press feedback ultraFast–faster.
- Flyouts and dialogs: normal–slow; nothing longer than 500ms. Honour `prefers-reduced-motion` (fade only).

## Components

- **Button** appearances: `primary` (one per view), `secondary` (default), `outline`, `subtle`, `transparent`. Sizes small/medium/large. Icon-only buttons need `aria-label`.
- **Input/Field**: wrap inputs in `Field` for label, hint and validation message (`validationState`); underline/filled-darker appearances only on tinted backgrounds.
- **Lists and tables**: `DataGrid`/`Table` with sortable headers, row selection by checkbox, density via size.
- **Navigation**: `TabList` for in-page views, `Nav` drawer for app sections, `Breadcrumb` for hierarchy.
- **Dialogs**: modal for decisions; non-modal `Drawer` for side tasks. Primary action on the right.
- **Feedback**: `MessageBar` inline (intent info/success/warning/error), `Toast` transient, `Spinner`/`Skeleton` for loading; empty states with one action.

## Accessibility

- Text contrast ≥ 4.5:1, UI components ≥ 3:1; neutral foreground tokens on neutral backgrounds are pre-checked, custom pairs are not.
- Focus: Fluent's focus indicator (2px `colorStrokeFocus2` outer + `colorStrokeFocus1` inner), shown only on keyboard focus (`createFocusOutlineStyle`).
- Full keyboard support with arrow-key navigation in composite widgets (`useArrowNavigationGroup`, Tabster).
- Support Windows high contrast / `forced-colors`: borders must exist even when transparent.
- Targets ≥ 24×24px (WCAG 2.2), 32px+ for primary controls; 44px on touch.

## Rules for agents

- Use Fluent UI React v9 (`@fluentui/react-components`) with `FluentProvider theme={webLightTheme | webDarkTheme}` (or a custom brand ramp via `createLightTheme(brandRamp)`); Web Components `@fluentui/web-components` outside React.
- Style with `makeStyles` + `tokens` (`tokens.colorNeutralForeground1`, `tokens.spacingHorizontalM`); never hardcode hex, px spacing or radius.
- Typography through `Text`/`Title1…` components or `typographyStyles`; never set font sizes by hand.
- Use alias tokens, not global ramps (`colorBrandBackground`, not `brand80`).
- Every screen works in light, dark and high contrast; check with forced-colors emulation.
- Prefer Fluent components over custom ones; a custom component composes Fluent hooks (`useButton_unstable`…) to keep behaviour and a11y.
