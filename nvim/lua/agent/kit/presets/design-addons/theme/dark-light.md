<!-- name: Dark and light -->
<!-- desc: both themes, following the system setting, with a manual override; every token defined for both -->
<!-- for: all -->
<!-- default: gui -->

## Color

- Every token has a light and a dark value; the app follows `prefers-color-scheme` (or the OS setting) and offers a manual Light / Dark / System switch.
- Dark is not inverted light: surfaces get lighter as they rise, saturated colors are toned down (lower chroma) to avoid glare.

## Rules for agents

- Never write a color that only exists in one theme; test every screen in both before it is done.
