<!-- name: Dithering -->
<!-- desc: ordered (Bayer) dithering for images, gradients and shadows: a 1-bit, print-like texture -->
<!-- for: all -->
<!-- default: retro-pixel -->

## Color

- Gradients and images are reduced to the palette with ordered dithering (Bayer 4×4 or 8×8); error diffusion (Floyd-Steinberg) only for photos.

## Shape and elevation

- Shadows and fills use dither patterns instead of opacity; GUI renders at integer scale with `image-rendering: pixelated`.
- TUI: dithering with block/shade characters `░▒▓` or braille dots for sub-cell detail.

## Rules for agents

- Dither at build time or once at load, never per frame.
