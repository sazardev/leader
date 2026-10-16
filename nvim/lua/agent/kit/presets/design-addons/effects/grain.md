<!-- name: Grain -->
<!-- desc: a fine noise texture over surfaces for warmth and depth, never over text -->
<!-- for: gui -->

## Shape and elevation

- Grain is a tiled 128×128 noise image (or SVG `feTurbulence`, baseFrequency 0.8) at 4-8% opacity with `mix-blend-mode: overlay`, on backgrounds and large surfaces only.
- Never animated, never over text or icons; disabled in high-contrast and print.

## Rules for agents

- One shared grain asset under 10 KB; do not generate noise per component.
