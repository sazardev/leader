<!-- name: Material 3 -->
<!-- desc: Google's adaptive system: tonal color roles, 4dp grid, shape scale, emphasized easing -->

# DESIGN.md: Material 3

Material Design 3 (Material You), Google's open design system for Android, web and Flutter. Source of truth: m3.material.io.
Colors come from a seed color through tonal palettes (HCT color space); every UI color is a **role**, never a raw value.

## Principles

- **Roles, not colors**: components ask for `primary`, `surface-container`, `on-surface`; the theme decides the value, so light, dark and dynamic color work for free.
- **Adaptive**: one layout that changes with the window size class (compact, medium, expanded, large, extra-large), not one design per device.
- **Hierarchy through tone and containment**: surface containers of different tones separate areas; elevation is mostly tonal, shadows are rare.
- **Personal but accessible**: dynamic color may come from the wallpaper or brand seed, contrast between a role and its `on-` role is always guaranteed.
- **Motion explains**: transitions show where things come from and go to, with emphasized easing for large movements.

## Color

Baseline scheme (seed `#6750A4`). Generate a brand scheme with Material Theme Builder and keep the same role names.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `primary` | `#6750A4` | `#D0BCFF` | Key actions, FAB, active states |
| `on-primary` | `#FFFFFF` | `#381E72` | Text/icons on primary |
| `primary-container` | `#EADDFF` | `#4F378B` | Tonal buttons, selected chips |
| `on-primary-container` | `#21005D` | `#EADDFF` | Text on primary-container |
| `secondary` | `#625B71` | `#CCC2DC` | Less prominent components |
| `secondary-container` | `#E8DEF8` | `#4A4458` | Navigation indicator, tonal elements |
| `tertiary` | `#7D5260` | `#EFB8C8` | Contrasting accents |
| `error` | `#B3261E` | `#F2B8B5` | Errors, destructive actions |
| `on-error` | `#FFFFFF` | `#601410` | Text on error |
| `error-container` | `#F9DEDC` | `#8C1D18` | Error banners |
| `surface` | `#FEF7FF` | `#141218` | App background |
| `surface-container-lowest` | `#FFFFFF` | `#0F0D13` | Lowest emphasis container |
| `surface-container-low` | `#F7F2FA` | `#1D1B20` | Cards (elevated) |
| `surface-container` | `#F3EDF7` | `#211F26` | Navigation bar, menus |
| `surface-container-high` | `#ECE6F0` | `#2B2930` | Dialogs |
| `surface-container-highest` | `#E6E0E9` | `#36343B` | Filled text fields, cards (filled) |
| `on-surface` | `#1D1B20` | `#E6E0E9` | Body text |
| `on-surface-variant` | `#49454F` | `#CAC4D0` | Secondary text, icons |
| `outline` | `#79747E` | `#938F99` | Borders of outlined components |
| `outline-variant` | `#CAC4D0` | `#49454F` | Dividers |
| `inverse-surface` | `#322F35` | `#E6E0E9` | Snackbars |
| `scrim` | `#000000` | `#000000` | Behind modals, at 32% opacity |

- Success and warning are not M3 roles: add them as **custom colors** harmonized to the seed (Theme Builder), each with `on-`, `container` and `on-container`.
- State layers: hover 8%, focus 10%, pressed 10%, dragged 16% of the `on-` color over the component. Disabled: content 38%, container 12% of `on-surface`.

## Typography

Font: Roboto (Android/web) or a brand font through the `brand`/`plain` typeface tokens; Roboto Flex for variable weights.

| Role | Size / line height | Weight | Tracking | Use |
| --- | --- | --- | --- | --- |
| display-large | 57 / 64 | 400 | -0.25 | Hero numbers, splash |
| display-medium | 45 / 52 | 400 | 0 | |
| display-small | 36 / 44 | 400 | 0 | |
| headline-large | 32 / 40 | 400 | 0 | Screen titles on large windows |
| headline-medium | 28 / 36 | 400 | 0 | |
| headline-small | 24 / 32 | 400 | 0 | Dialog titles |
| title-large | 22 / 28 | 400 | 0 | Top app bar |
| title-medium | 16 / 24 | 500 | 0.15 | Card titles, list headers |
| title-small | 14 / 20 | 500 | 0.1 | |
| body-large | 16 / 24 | 400 | 0.5 | Main text |
| body-medium | 14 / 20 | 400 | 0.25 | Default text in components |
| body-small | 12 / 16 | 400 | 0.4 | Supporting text |
| label-large | 14 / 20 | 500 | 0.1 | Buttons, tabs |
| label-medium | 12 / 16 | 500 | 0.5 | Chips, badges |
| label-small | 11 / 16 | 500 | 0.5 | Small labels |

Sizes in sp (Android) / px (web, 1:1 at 16px root). Use tabular figures for numbers in tables and counters.

## Spacing and layout

- 4dp base grid; component internals on 4dp, layout on 8dp. Scale: 0, 4, 8, 12, 16, 24, 32, 40, 48, 64.
- Window size classes: compact < 600, medium 600–839, expanded 840–1199, large 1200–1599, extra-large ≥ 1600 (dp).
- Margins: 16dp compact, 24dp medium and up. Panes: one in compact, list-detail with two panes from expanded.
- Navigation: navigation bar (compact), navigation rail (medium/expanded), navigation drawer or expanded rail (large+).
- Body text measure: 40–60 characters per line on large windows; never stretch text across a wide pane.

## Shape and elevation

| Shape token | Radius | Typical components |
| --- | --- | --- |
| none | 0 | Full-screen sheets, top app bar |
| extra-small | 4dp | Text fields (top corners), snackbars, menus |
| small | 8dp | Chips |
| medium | 12dp | Cards |
| large | 16dp | FAB, navigation drawer, side sheets |
| extra-large | 28dp | Dialogs, bottom sheets (top corners), search bar |
| full | 50% | Buttons, badges, switches, navigation indicator |

Elevation levels (dp): 0, 1, 3, 6, 8, 12. Elevation is shown with **surface tone** first (surface-container-low → highest); shadows only on FAB, elevated buttons/cards, menus, and dragged items.

## Motion

| Token | Value |
| --- | --- |
| easing-emphasized | `cubic-bezier(0.2, 0, 0, 1)` |
| easing-emphasized-decelerate | `cubic-bezier(0.05, 0.7, 0.1, 1)` |
| easing-emphasized-accelerate | `cubic-bezier(0.3, 0, 0.8, 0.15)` |
| easing-standard | `cubic-bezier(0.2, 0, 0, 1)` |
| easing-standard-decelerate | `cubic-bezier(0, 0, 0, 1)` |
| easing-standard-accelerate | `cubic-bezier(0.3, 0, 1, 1)` |
| duration-short1…4 | 50, 100, 150, 200 ms |
| duration-medium1…4 | 250, 300, 350, 400 ms |
| duration-long1…4 | 450, 500, 550, 600 ms |

- Enter with decelerate, exit with accelerate; exits are shorter than entries.
- Small utility changes (state layers, icons): short durations. Containers that move across the screen: medium/long with emphasized easing.
- Transition patterns: container transform, shared axis (x/y/z), fade through, fade. Respect `prefers-reduced-motion`: replace movement with fades.

## Components

- **Buttons**, by emphasis: filled (one primary action per view) > tonal > elevated > outlined > text. Height 40dp, full radius, label-large, 24dp horizontal padding (16dp with icon).
- **FAB** only for the screen's primary constructive action; never two FABs.
- **Text fields**: filled or outlined, never mixed in one form. Label always visible (floats on focus), supporting text for help/errors, error replaces supporting text.
- **Lists**: one-, two- and three-line items (56/72/88dp), leading icon/avatar, trailing meta or control.
- **Navigation**: 3–5 destinations in a navigation bar; the active one with the pill indicator in `secondary-container`.
- **Dialogs**: basic dialogs for decisions only; full-screen dialogs for multi-field tasks on compact windows. Confirming button on the right.
- **Snackbars**: brief feedback at the bottom, one action at most, never for critical errors.
- **States**: every screen designs loading (progress indicators, skeletons only for content), empty (illustration or icon + one action) and error (message + retry).

## Accessibility

- Text contrast ≥ 4.5:1 (3:1 for large text and UI parts); the role pairs (`primary`/`on-primary`…) guarantee it, custom combinations must be checked.
- Touch targets ≥ 48×48dp even when the visual element is smaller.
- Focus indicator: 3dp outline in `secondary`, offset 2dp, visible on keyboard focus.
- Every icon button has an accessible label; never color alone to convey state (add icon or text).
- Supports 200% text scaling without loss of content; layouts reflow instead of truncating.

## Rules for agents

- Use the platform implementation: Jetpack Compose `MaterialTheme` (Material3), Flutter `ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(...))`, web `@material/web` or CSS custom properties `--md-sys-color-*`, `--md-sys-typescale-*`, `--md-sys-shape-*`.
- Never hardcode a hex, size or radius in a component: read the role/token. A missing token is added to the theme first.
- Pick components by emphasis level (above), not by look; one filled button per view.
- Build every screen for compact first, then adapt at the medium and expanded breakpoints.
- Every interactive element implements hover, focus, pressed and disabled with state layers.
- Dark theme is not optional: test every screen in both.
