<!-- name: ASCII gradients -->
<!-- desc: truecolor gradients over ASCII and block characters, density ramps, figlet banners -->
<!-- for: tui -->
<!-- default: ascii-art -->

## Color

- Gradients interpolate in OKLCH between 2-3 stops per character cell (foreground color per cell); 256-color fallback picks the nearest index, ANSI 16 falls back to one solid accent.

## Typography

- Density ramps map brightness to characters, darkest to brightest: short ` .:-=+*#%@` (10 levels), block ` ░▒▓█`, half blocks `▀▄` (double vertical resolution), and the long 70-level ramp:

```
 .'`^",:;Il!i><~+_-?][}{1)(|\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$
```
- Banners in figlet/toilet fonts (`ANSI Shadow`, `Big`, `Slant`, `Small`), at most one per screen, never wider than the terminal (fall back to a smaller font, then to plain bold text).

## Components

- Art is data: banners and images live in asset files or are generated at startup, never hand-typed into view code.

## Accessibility

- Screen readers and `NO_COLOR` get the plain text the art spells, never the art itself.
