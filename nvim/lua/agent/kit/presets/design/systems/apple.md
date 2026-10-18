<!-- name: Apple HIG -->
<!-- desc: human interface: SF Pro, rounded controls, translucency, calm spacing, system colors -->

# DESIGN.md: Apple HIG

The look of Apple's Human Interface Guidelines: calm, legible, system-driven UI with SF Pro, rounded controls,
translucency, generous spacing and system colors. Source: Apple HIG (developer.apple.com/design); values are from the
guidelines and marked "(approx.)" where they vary between platforms or versions.

## Principles

- **Clarity**: text is legible, icons are precise, and adornments are subtle; content is the focus.
- **Deference**: the UI helps people understand and interact with content without competing with it.
- **Depth**: visual layers and realistic motion convey hierarchy and facilitate understanding.
- **Consistency**: familiar patterns and system components reduce cognitive load.
- **Accessibility**: Dynamic Type, VoiceOver and contrast are first-class, not afterthoughts.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#FFFFFF` | `#000000` | App background |
| `surface` | `#F2F2F7` (approx.) | `#1C1C1E` (approx.) | Grouped surfaces, cards |
| `surface-raised` | `#FFFFFF` (approx.) | `#2C2C2E` (approx.) | Sheets, popovers, modals |
| `text` | `#000000` | `#FFFFFF` | Body text, headings |
| `text-muted` | `#3C3C43` (approx., 60% opacity) | `#EBEBF5` (approx., 60% opacity) | Secondary text, metadata |
| `text-faint` | `#3C3C43` (approx., 30% opacity) | `#EBEBF5` (approx., 30% opacity) | Placeholders, hints |
| `border` | `#C6C6C8` (approx.) | `#38383A` (approx.) | 1px separators |
| `accent` | `#007AFF` | `#0A84FF` | Tint color, links, focus |
| `on-accent` | `#FFFFFF` | `#FFFFFF` | Text on accent |
| `success` | `#34C759` | `#30D158` | Success states |
| `warning` | `#FF9500` | `#FF9F0A` | Warnings |
| `danger` | `#FF3B30` | `#FF453A` | Destructive actions, errors |

- System colors adapt to light/dark and accessibility settings; prefer system colors over custom ones.
- Translucency (materials) separates layers while keeping context visible.

## Typography

Fonts: SF Pro (SF Pro Text for body, SF Pro Display for large) on Apple platforms; SF Mono for code. (approx.)

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| Large Title | 34px / 41px | 700 | Navigation large titles (approx.) |
| Title 1 | 28px / 34px | 700 | Page titles (approx.) |
| Title 2 | 22px / 28px | 700 | Section titles (approx.) |
| Title 3 | 20px / 25px | 600 | Subsection titles (approx.) |
| Headline | 17px / 22px | 600 | Emphasized body (approx.) |
| Body | 17px / 22px | 400 | Default text (approx.) |
| Callout | 16px / 21px | 400 | Secondary text (approx.) |
| Subheadline | 15px / 20px | 400 | Supporting text (approx.) |
| Footnote | 13px / 18px | 400 | Footnotes (approx.) |
| Caption | 12px / 16px | 400 | Captions (approx.) |

- Dynamic Type scales all text; layouts must adapt to larger sizes.
- Prefer system text styles over custom font sizes.

## Spacing and layout

- 8px base; common steps 8, 16, 24, 32, 40 (approx.).
- Use safe areas and standard margins; avoid edge-to-edge content on mobile.
- Grouped lists use 16px horizontal padding and 8px vertical gaps (approx.).
- Navigation bars and toolbars use standard heights and blur materials.

## Shape and elevation

- Radius: 8–12px (buttons, cards), 16–20px (sheets, modals) (approx.).
- Materials: ultra-thin, thin, regular, thick and chrome for translucency layers.
- Elevation via materials and shadows; floating layers use soft shadows plus blur.
- Borders are rare; separation comes from materials and spacing.

## Motion

| Token | Value |
| --- | --- |
| duration-fast | 150–200ms (approx.) |
| duration-default | 250–350ms (approx.) |
| easing | spring / ease-in-out (approx.) |

- Motion is purposeful and physics-based; use springs for interactive transitions.
- Reduced motion: disable parallax and large movements; keep fades.
- Haptics reinforce key actions on supported devices.

## Components

- **Navigation bar**: large or standard title, back button, and trailing actions; blurs content behind.
- **Lists**: grouped or plain, with separators, swipe actions and disclosure indicators.
- **Buttons**: tinted, filled, gray and bordered styles; rounded, with haptic feedback.
- **Sheets and modals**: rounded cards that slide up; dismiss by swipe or tap outside.
- **Alerts and action sheets**: centered or bottom-anchored, with clear destructive actions in red.
- **Search**: search field with cancel, often in a navigation bar.
- **Empty states**: centered icon, title and one action.

## Accessibility

- Dynamic Type scales text up to accessibility sizes; layouts must not clip.
- VoiceOver labels and hints for every control; traits describe role and state.
- Increase Contrast and Reduce Motion settings are respected.
- Color never alone for status; icons and labels accompany color.
- Targets ≥ 44px on touch; larger for accessibility.

## Rules for agents

- Prefer system colors, materials and text styles over custom values.
- Support Dynamic Type and accessibility settings (contrast, motion, bold text).
- Use safe areas and standard margins; avoid edge-to-edge content on mobile.
- Prefer translucency and materials for layering; keep shadows soft.
- Keep motion purposeful and physics-based; respect Reduce Motion.
- Every interactive element needs an accessible label and role.
filePath: /home/sazar/Documents/my-nvim-setup/nvim/lua/agent/kit/presets/design/systems/apple.md