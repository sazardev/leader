<!-- name: Mobile app -->
<!-- desc: native-feeling phones and tablets: safe areas, 44/48 pt targets, gestures, bottom navigation, haptics -->
<!-- for: gui -->

## Spacing and layout

- Respect safe areas (notch, home indicator, status bar): content padded by the platform insets, backgrounds may bleed under them.
- Phone first (360-430 pt wide), tablet layouts at ≥ 600 pt use two panes (list-detail).
- Primary actions in the thumb zone: the lower half of the screen.

## Components

- Bottom navigation with 3-5 destinations; back follows the platform (swipe on iOS, system back on Android).
- Touch targets at least 44×44 pt (iOS) / 48×48 dp (Android), 8 pt apart.
- Gestures (swipe to delete, pull to refresh) always have a visible alternative.
- Haptics only to confirm meaningful actions (success, selection, error), never on scroll.

## Rules for agents

- Use the platform's text scaling (Dynamic Type / font scale) and test at the largest setting.
- Never place interactive elements under the status bar or the home indicator.
