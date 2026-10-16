<!-- name: Playful -->
<!-- desc: friendly and rounded: bold colors, chunky buttons with depth, bouncy motion, mascot and celebration ready -->

# DESIGN.md: Playful

A friendly, game-like style: bold saturated colors, chunky rounded buttons with a solid bottom edge, bouncy motion and
room for a mascot and celebrations. Suits learning apps, habits, kids and consumer products that reward progress.

## Principles

- **Celebrate progress**: completing something always gets feedback (sound-free by default, motion and color).
- **Chunky and tappable**: big targets, thick shapes, obvious affordances.
- **Bold color with discipline**: each color has one job (action, success, error, streak).
- **Friendly voice**: short sentences, encouraging copy, no blame in errors.
- **Fun never blocks**: animations are short and skippable.

## Color

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | `#FFFFFF` | `#131F24` | Page |
| `surface` | `#F7F7F7` | `#1B2B32` | Cards |
| `border` | `#E5E5E5` | `#37464F` | Card and button edges |
| `text` | `#3C3C3C` | `#F1F7FB` | Text |
| `text-muted` | `#777777` | `#A6B4BB` | Hints |
| `action` | `#1CB0F6` | `#49C0F8` | Primary buttons |
| `action-edge` | `#1899D6` | `#1F8EC4` | Bottom edge of primary buttons |
| `success` | `#58CC02` | `#79D634` | Correct, complete |
| `success-edge` | `#58A700` | `#5AAA1F` | Edge |
| `danger` | `#FF4B4B` | `#FF6B6B` | Wrong, error |
| `streak` | `#FF9600` | `#FFB020` | Streaks, rewards |
| `premium` | `#CE82FF` | `#D9A0FF` | Special items |

Values are a starting palette (approx.), swap for the brand; keep one job per color.

## Typography

Font: Nunito, Feather-like rounded sans (`"Nunito", ui-rounded, system-ui, sans-serif`), weights 700–900 for UI.

| Role | Size / line height | Weight | Use |
| --- | --- | --- | --- |
| display | 40 / 46 | 900 | Celebrations |
| h1 | 28 / 34 | 800 | Screen titles |
| h2 | 22 / 28 | 800 | Sections |
| body | 17 / 26 | 600 | Text |
| button | 15 / 20 | 800, uppercase, +0.04em | Buttons |
| caption | 13 / 18 | 700 | Hints, labels |

## Spacing and layout

- 4px base; scale 4, 8, 12, 16, 20, 24, 32, 48.
- Mobile first: one column, max width 600px for lessons/forms, 1080px for home with a side rail on desktop.
- Bottom navigation on mobile (5 items max), side rail on desktop.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| `radius-md` | 12px | Inputs, small cards |
| `radius-lg` | 16px | Buttons, cards |
| `radius-full` | 999px | Badges, progress bars |
| `edge` | `0 4px 0 <color>-edge` | Buttons and selectable cards (solid bottom edge) |
| `edge-pressed` | `0 0 0` + translateY(4px) | Pressed |
| `border-card` | 2px `border` | Cards |

No blurred shadows: depth is the solid bottom edge.

## Motion

| Token | Value |
| --- | --- |
| `duration-tap` | 100ms |
| `duration-pop` | 300ms |
| `bounce` | `cubic-bezier(0.34, 1.56, 0.64, 1)` |
| `celebrate` | 900ms (confetti/burst), skippable |

- Press: drop by the edge height (4px) in `duration-tap`.
- Correct answer: card pops (scale 1 → 1.05 → 1) with `bounce`; streak counter flips.
- Reduced motion: no bounce, no confetti; color and text feedback stay.

## Components

- **Primary button**: full width on mobile, 50px high, `action` fill, `edge`.
- **Selectable card** (answers, options): border-card + edge; selected = action border + light action tint.
- **Progress bar**: 16px, `radius-full`, success fill with a highlight stripe.
- **Feedback sheet**: slides up from the bottom: success or danger tint, title, explanation, continue button.
- **Mascot slot**: an illustration area in empty states and celebrations, never over content.
- **States**: empty (mascot + encouraging line + action), loading (bouncing dots, reduced motion: static), error (friendly message + retry).

## Accessibility

- White text on `action`/`success` must meet 4.5:1 at button size (bold 15px counts as normal text: darken the fill if needed); verify each brand swap.
- Feedback never only by color: icon (✓ / ✗) and text too.
- Celebrations are skippable and never auto-advance faster than 3s.
- Targets ≥ 48×48px; spacing ≥ 8px.

## Rules for agents

- Depth is always the solid `edge`; never blurred box shadows.
- Each color keeps its job: never use `danger` for decoration or `streak` for actions.
- Every completion path has feedback (motion + color + text); every error copy is encouraging and says what to do.
- Respect reduced motion for every animation, including confetti.
- Mascot and illustrations are optional slots; layouts work without them.
