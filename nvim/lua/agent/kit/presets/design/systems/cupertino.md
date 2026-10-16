<!-- name: Cupertino -->
<!-- desc: Apple Human Interface Guidelines: SF Pro, Dynamic Type, system colors, 44pt targets, Liquid Glass -->

# DESIGN.md: Cupertino

Apple's Human Interface Guidelines for iOS, iPadOS and macOS, as implemented by SwiftUI/UIKit (and Flutter's Cupertino
widgets). Source of truth: developer.apple.com/design/human-interface-guidelines. Colors, fonts and materials are
**semantic system values** that adapt to light/dark, contrast settings, Dynamic Type and the platform.

## Principles

- **Hierarchy**: controls and chrome defer to content; the content layer is what the user came for.
- **Harmony**: follow the platform's shapes, spacing and behaviours so the app feels native next to system apps.
- **Consistency**: standard components and gestures do what users expect (swipe back, pull to refresh, share sheet).
- **Clarity**: legible text at every size, precise icons (SF Symbols), purposeful color.
- **Depth**: layers, materials and motion communicate where you are and where things come from.

## Color

System colors (iOS, default contrast). Always use the semantic name; the values adapt automatically.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `systemBlue` (tint) | `#007AFF` | `#0A84FF` | Default tint, links, primary actions |
| `systemGreen` | `#34C759` | `#30D158` | Success, toggles on |
| `systemRed` | `#FF3B30` | `#FF453A` | Destructive, errors |
| `systemOrange` | `#FF9500` | `#FF9F0A` | Warnings |
| `systemYellow` | `#FFCC00` | `#FFD60A` | Highlights |
| `systemIndigo` | `#5856D6` | `#5E5CE6` | Accents |
| `systemPurple` | `#AF52DE` | `#BF5AF2` | Accents |
| `systemPink` | `#FF2D55` | `#FF375F` | Accents |
| `systemGray` | `#8E8E93` | `#8E8E93` | Secondary icons |
| `systemBackground` | `#FFFFFF` | `#000000` | Main background (plain lists) |
| `secondarySystemBackground` | `#F2F2F7` | `#1C1C1E` | Grouped content, cards |
| `tertiarySystemBackground` | `#FFFFFF` | `#2C2C2E` | Content on secondary |
| `systemGroupedBackground` | `#F2F2F7` | `#000000` | Background of grouped lists |
| `label` | `#000000` | `#FFFFFF` | Primary text |
| `secondaryLabel` | `rgba(60,60,67,0.6)` | `rgba(235,235,245,0.6)` | Secondary text |
| `tertiaryLabel` | `rgba(60,60,67,0.3)` | `rgba(235,235,245,0.3)` | Placeholders |
| `separator` | `rgba(60,60,67,0.29)` | `rgba(84,84,88,0.6)` | Hairlines between rows |

- One app tint (accent color) for interactive elements; text that is tappable uses the tint, not underline.
- Increased-contrast variants exist for every system color; custom colors must define them too (asset catalog: Any/Dark + High Contrast).

## Typography

SF Pro (SF Pro Text/Display chosen automatically by size), SF Pro Rounded and New York optional; SF Mono for code. Dynamic Type, default (Large) size:

| Style | Size / leading (pt) | Weight | Use |
| --- | --- | --- | --- |
| Large Title | 34 / 41 | Regular | Top-level screen titles (collapses on scroll) |
| Title 1 | 28 / 34 | Regular | |
| Title 2 | 22 / 28 | Regular | Section headers in content |
| Title 3 | 20 / 25 | Regular | |
| Headline | 17 / 22 | Semibold | Row titles, emphasized body |
| Body | 17 / 22 | Regular | Main text |
| Callout | 16 / 21 | Regular | Secondary content blocks |
| Subheadline | 15 / 20 | Regular | Row subtitles |
| Footnote | 13 / 18 | Regular | List footers, meta |
| Caption 1 | 12 / 16 | Regular | Labels under images |
| Caption 2 | 11 / 13 | Regular | Smallest text (never smaller) |

- Always use text styles (`.font(.body)`), never fixed point sizes, so Dynamic Type (xSmall … AX5) scales the UI.
- macOS body is 13pt; use the platform text styles, not iOS numbers, on Mac.

## Spacing and layout

- 8pt rhythm with 4pt for fine steps; standard margins 16pt (compact width) and 20pt (regular width); respect safe areas and layout margins.
- Navigation bar 44pt (plus large title area), tab bar 49pt (83pt including the home indicator area on Face ID devices), toolbar 44pt; list rows ≥ 44pt.
- Size classes: compact/regular width and height. iPad and Mac use split views (sidebar + content + detail); iPhone uses stacks and tabs.
- Readable content width (`readableContentGuide`) for long text on wide screens.

## Shape and elevation

- Corners are **continuous** (squircle-like), not circular arcs: `RoundedRectangle(cornerRadius:, style: .continuous)`.
- Typical radii (approx.): grouped list sections 10pt, cards 12–16pt, sheets/modals ~ device corner radius, buttons capsule or 8–12pt.
- Depth through **materials** (blur + vibrancy: ultraThin, thin, regular, thick, chrome) and layering, not heavy shadows.
- **Liquid Glass** (iOS/iPadOS/macOS 26): controls and navigation (tab bars, toolbars, sidebars, sheets) float above content in a translucent, refracting material that adapts to what is behind it. Use it for the navigation/control layer only, never for content; system components adopt it automatically.

## Motion

- Default to **spring** animations (`.spring`, `.smooth`, `.snappy`, `.bouncy` in SwiftUI); `.smooth` (no bounce) for most UI, `.snappy` for quick feedback, `.bouncy` sparingly.
- Typical spring response 0.3–0.5s (approx.); keep interactive transitions interruptible and gesture-driven (the back swipe follows the finger).
- Use system transitions: push/pop, sheet presentation, zoom (matched geometry) from a tapped item to its detail.
- Reduce Motion: replace slides and zooms with cross-fades (`@Environment(\.accessibilityReduceMotion)`).
- Haptics accompany meaningful moments (success, selection change), never every tap.

## Components

- **Navigation**: `NavigationStack` with large titles at the top level, inline titles deeper; tab bar for 3–5 top-level sections; sidebar on iPad/Mac.
- **Buttons**: system styles (`.borderedProminent` for the one primary action, `.bordered`, `.plain`); destructive role in red; labels are verbs.
- **Lists**: `List` with `.insetGrouped` for settings/forms, `.plain` for content; swipe actions for row operations; disclosure chevrons for navigation.
- **Forms**: `Form` with sections and footers explaining choices; toggles for on/off, pickers for choices; Done/Cancel in the navigation bar.
- **Sheets and alerts**: sheets (with detents) for focused tasks; alerts only for important decisions, max two/three buttons, Cancel in bold position per platform.
- **Feedback**: inline progress (`ProgressView`), pull to refresh, empty states with `ContentUnavailableView`.
- **Icons**: SF Symbols matched to text weight and scale; custom icons follow the symbol grid.

## Accessibility

- Hit targets ≥ 44×44pt on iOS (28×28 on macOS for small controls).
- Support Dynamic Type up to the accessibility sizes: layouts switch from horizontal to vertical stacks when text is large.
- VoiceOver: every element has a label, value and traits; group related elements; custom actions for swipe actions.
- Contrast ≥ 4.5:1 for text; support Increase Contrast, Reduce Transparency (materials become solid) and Bold Text.
- Never color alone; respect Smart Invert and Differentiate Without Color.

## Rules for agents

- SwiftUI first: system components, `.font(.textStyle)`, `Color(.label)`/`.primary`/`.secondary`, `.tint(...)` for the accent, asset catalog colors with dark and high-contrast variants.
- Never hardcode point sizes for text, hex colors, or shadows that the system provides; never fake Liquid Glass with custom blur on content.
- Use SF Symbols (`Image(systemName:)`) before custom icons.
- Use `NavigationStack`/`NavigationSplitView`, `TabView`, `List`, `Form`, `.sheet`, `.alert` instead of custom chrome.
- Animate with springs (`withAnimation(.smooth)`); check `accessibilityReduceMotion` for large movement.
- Every screen works in light, dark, the largest Dynamic Type size and with VoiceOver before it is done.
- Flutter: `CupertinoApp`, `CupertinoTheme`, `CupertinoColors.systemBlue` (resolved with `CupertinoDynamicColor.resolve`), Cupertino widgets, never Material widgets on these screens.
