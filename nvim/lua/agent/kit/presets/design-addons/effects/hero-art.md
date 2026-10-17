<!-- name: Hero art -->
<!-- desc: the art is the identity: allowed on the main screen, framed and centered, the value still in plain text -->
<!-- for: ascii-art braille synthwave retro -->

## Principles

- **Hero screen**: this app's identity is its art, so the main screen carries it (a big glyph display, a scene, a banner that is also the readout). This overrides "art only on splash/empty/about screens" for the main screen alone; secondary screens, lists and dialogs stay plain.

## Spacing and layout

- The main screen is one centered composition: the art block, then the controls under it, both inside one frame, centered horizontally and vertically in the window.
- The art block has a fixed, designed size at the minimum terminal size and grows in steps (never stretched per cell); below the minimum it swaps to a compact variant.
- Leave at least one empty cell between the art and its frame and between the frame and the window edge.

## Components

- **Hero display**: the art renders the live value (big glyph digits, a gauge, a scene state); the exact value is also shown as plain text in one line under or beside it.
- **Controls under a hero**: aligned to the art's width (a keypad or button row centered under the display, cells of equal width), so the composition reads as one object.

## Accessibility

- The plain-text line carries the same value as the hero art, so screen readers and `NO_COLOR` lose nothing.
