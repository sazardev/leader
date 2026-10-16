<!-- name: High contrast -->
<!-- desc: maximum legibility: 7:1 text, solid borders, no information in subtle tints -->
<!-- for: all -->

## Color

- Text contrast at least 7:1, UI boundaries at least 4.5:1; no grey-on-grey, no meaning carried by tints alone.
- Honour `prefers-contrast: more` and Windows forced colors (`forced-colors: active`, system color keywords) on GUI; ANSI bright colors on TUI.

## Shape and elevation

- Every interactive element has a solid 1-2 px border; elevation is shown with borders, never with shadows alone.

## Accessibility

- Focus indicator 3 px, contrasting with both the element and its background.
