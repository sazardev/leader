<!-- name: CRT -->
<!-- desc: scanlines, phosphor glow and slight curvature: the look of a cathode-ray tube -->
<!-- for: all -->
<!-- default: retro -->

## Color

- Glow: text gets a soft halo of its own color (GUI `text-shadow: 0 0 2px currentColor, 0 0 8px color-mix(in oklch, currentColor 40%, transparent)`); TUI keeps the palette's brightest step for focus to imitate it.

## Shape and elevation

- GUI scanlines: a fixed overlay `repeating-linear-gradient(to bottom, rgb(0 0 0 / 0.15) 0 1px, transparent 1px 3px)`, pointer-events none; optional vignette and 1-2% barrel curvature via a shader or SVG filter.
- TUI: no overlays; the effect comes from the phosphor palette, a dim surface one step above the background and generous blank lines.

## Accessibility

- Scanlines and glow are off with reduced motion/transparency preferences or high contrast; body text never sits under the overlay at less than 7:1.
