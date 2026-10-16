<!-- name: M3 Expressive -->
<!-- desc: Material 3 Expressive (2025): M3 roles plus spring motion, shape morphing, emphasized type -->

# DESIGN.md: M3 Expressive

Material 3 Expressive, the 2025 evolution of Material Design 3. It keeps every M3 token (color roles, type scale, shape
scale, window size classes) and adds a physics-based motion system, a larger shape library with morphing, emphasized
typography and new components. Source of truth: m3.material.io (Expressive updates). Where a value below says "reference",
check m3.material.io before relying on its precision.

## Principles

- **Expressive with purpose**: emotion (shape, color, motion, type) is used to guide attention to the key action, not everywhere.
- **Roles still rule**: components ask for M3 roles (`primary`, `surface-container-high`…); expressiveness never means raw colors.
- **Physics, not curves**: motion is driven by springs, so interruptions and gestures feel continuous.
- **Hierarchy by contrast**: bigger, bolder, more colorful for the one thing that matters; calm for the rest.
- **Accessible first**: larger targets, stronger contrast in emphasized states, reduced-motion fallbacks.

## Color

Same role system and baseline as M3 (seed `#6750A4`); Expressive leans on higher-chroma containers and tertiary accents.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `primary` | `#6750A4` | `#D0BCFF` | Key action, FAB, active toggle |
| `on-primary` | `#FFFFFF` | `#381E72` | Text/icons on primary |
| `primary-container` | `#EADDFF` | `#4F378B` | Emphasized buttons, selected states |
| `on-primary-container` | `#21005D` | `#EADDFF` | Text on primary-container |
| `secondary-container` | `#E8DEF8` | `#4A4458` | Toolbars, button groups (unselected) |
| `tertiary` | `#7D5260` | `#EFB8C8` | Expressive accents, highlights |
| `tertiary-container` | `#FFD8E4` | `#633B48` | Hero cards, celebratory moments |
| `error` | `#B3261E` | `#F2B8B5` | Errors, destructive actions |
| `surface` | `#FEF7FF` | `#141218` | App background |
| `surface-container` | `#F3EDF7` | `#211F26` | Navigation, docked toolbars |
| `surface-container-high` | `#ECE6F0` | `#2B2930` | Floating toolbars, menus |
| `on-surface` | `#1D1B20` | `#E6E0E9` | Body text |
| `on-surface-variant` | `#49454F` | `#CAC4D0` | Secondary text, icons |
| `outline-variant` | `#CAC4D0` | `#49454F` | Dividers |

- Brand schemes come from Material Theme Builder; dynamic color stays supported. Success/warning as harmonized custom colors.
- Use **vibrant** container colors (`*-container`, `tertiary`) on the single hero element of a screen; keep surfaces neutral.

## Typography

M3 type scale plus an **emphasized** variant of every role (heavier weight). Variable fonts preferred: Roboto Flex or Google Sans Flex (reference).

| Role | Size / line height | Weight (regular → emphasized) | Use |
| --- | --- | --- | --- |
| display-large | 57 / 64 | 400 → heavier (reference) | Hero numbers, onboarding |
| display-medium | 45 / 52 | 400 → heavier | |
| headline-large | 32 / 40 | 400 → heavier | Screen hero titles |
| headline-medium | 28 / 36 | 400 → heavier | |
| headline-small | 24 / 32 | 400 → heavier | Dialog titles |
| title-large | 22 / 28 | 400 → 500+ | App bar titles |
| title-medium | 16 / 24 | 500 → heavier | Card titles |
| body-large | 16 / 24 | 400 → 500 | Main text |
| body-medium | 14 / 20 | 400 → 500 | Component text |
| label-large | 14 / 20 | 500 → 600+ | Buttons |
| label-medium | 12 / 16 | 500 → 600+ | Chips, badges |

- Exact emphasized weights: reference, check m3.material.io (they are token values `*-emphasized`).
- Use emphasized type for the one element to read first (a key number, the primary label); never for whole paragraphs.

## Spacing and layout

- 4dp grid, layout on 8dp; scale 0, 4, 8, 12, 16, 24, 32, 40, 48, 64 (as M3).
- Window size classes: compact < 600, medium 600–839, expanded 840–1199, large 1200–1599, extra-large ≥ 1600 (dp).
- Margins 16dp compact, 24dp medium and up. Flexible navigation rail that expands into a drawer-like rail on large windows.
- Hero areas get generous space and larger shapes; dense areas (lists, settings) stay at M3 density.

## Shape and elevation

| Token | Radius | Use |
| --- | --- | --- |
| extra-small | 4dp | Menus, snackbars |
| small | 8dp | Chips |
| medium | 12dp | Cards |
| large | 16dp | FABs, sheets |
| large-increased | 20dp (reference) | Larger cards, hero containers |
| extra-large | 28dp | Dialogs, bottom sheets |
| extra-large-increased | 32dp (reference) | Expressive hero surfaces |
| extra-extra-large | 48dp (reference) | Large expressive containers |
| full | 50% | Buttons, toggles, indicators |

- **Shape library**: ~35 abstract shapes (cookie, clover, sunny, pill, burst, soft-burst…) for avatars, image masks and loading indicators. Use one or two per product, consistently.
- **Shape morphing**: shapes animate between states (a button that squares its corners when pressed, a selected toggle that changes shape); always through a spring.
- Elevation as M3: levels 0, 1, 3, 6, 8, 12 dp, tonal first, shadows only on floating elements (FAB, floating toolbar, menus).

## Motion

Motion is built from **springs** (damping ratio + stiffness), not duration + easing. Two families:

| Spring | Damping | Stiffness | Use |
| --- | --- | --- | --- |
| spatial fast (expressive) | 0.6 | 800 | Small components moving/resizing |
| spatial default (expressive) | 0.8 | 380 | Containers, sheets, position changes |
| spatial slow (expressive) | 0.8 | 200 | Full-screen transitions |
| effects fast | 1.0 | 3800 | Color, opacity on small parts |
| effects default | 1.0 | 1600 | Color/opacity of components |
| effects slow | 1.0 | 800 | Large fades |

- Values are reference (check m3.material.io): spatial springs may overshoot (bounce), **effects springs never do** (damping 1.0) because color and opacity must not overshoot.
- Two schemes: **expressive** (bouncier spatial springs, the default for hero moments) and **standard** (more damped, for utility UIs).
- Interruptible: a new gesture retargets the running spring; never wait for an animation to finish.
- Reduced motion: replace spatial springs with fades (effects springs) and disable shape morphing.

## Components

- **Buttons**: five sizes (XS, S, M, L, XL; reference) and round or square shape; the pressed state morphs the shape. Use L/XL only for the main action of a screen.
- **Button groups**: connected or standard groups of related actions; the pressed button widens and neighbours yield. Replace segmented buttons with connected button groups.
- **Split buttons**: a primary action plus a trailing menu of variants; the trailing part rotates/morphs on open.
- **FAB menu**: the FAB opens into a list of up to 6 related actions; replaces speed dials.
- **Toolbars**: docked (bottom, full width) or floating (pill, vibrant or standard color); replace the bottom app bar.
- **Loading indicator**: morphing-shape indicator for waits under ~5s; **wavy progress indicators** (linear and circular) for determinate progress.
- **Navigation**: short navigation bar, flexible navigation rail (collapsed/expanded), app bars with larger title options.
- **States**: loading (loading indicator, skeleton for content), empty (expressive shape + one action), error (message + retry).

## Accessibility

- Contrast ≥ 4.5:1 for text, 3:1 for UI and large text; vibrant containers still pair with their `on-` roles.
- Touch targets ≥ 48×48dp; button sizes XS/S keep a 48dp target area.
- Shape or size changes are never the only signal of state: pair them with color, icon or label change.
- Every animation respects reduced-motion; no infinite decorative motion outside loading indicators.
- 200% text scaling without loss; emphasized type must not truncate.

## Rules for agents

- Jetpack Compose: use the Material 3 Expressive APIs (`MaterialExpressiveTheme`, `MotionScheme.expressive()`, `ButtonGroup`, `SplitButtonLayout`, `FloatingToolbar`, `LoadingIndicator`, `MaterialShapes`; reference, check the current `material3` release). Flutter/web: follow M3 tokens and approximate springs with the platform's spring physics.
- Never hardcode colors, radii or durations: read M3 roles, shape tokens and motion scheme springs.
- Animate position/size with spatial springs and color/opacity with effects springs; never a cubic-bezier for new expressive motion.
- Use expressive emphasis (vibrant color, large shape, emphasized type, XL button) on ONE element per screen.
- Keep standard M3 components where expressiveness adds nothing (forms, settings, dense lists).
- Test light, dark and reduced-motion for every screen.
