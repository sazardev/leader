<!-- name: Neon glow -->
<!-- desc: neon glow on text and borders for accents: synthwave energy, used sparingly -->
<!-- for: all -->

## Color

- Neon accents: magenta `#FF2BD6`, cyan `#00F0FF`, violet `#9D4EDD` on near-black `#0B0612`.

## Shape and elevation

- GUI glow: `box-shadow: 0 0 6px var(--accent), 0 0 18px color-mix(in oklch, var(--accent) 50%, transparent)` on focus and primary elements only.
- TUI: bright ANSI colors (`13`, `14`) and bold for the glowing elements; everything else stays dim.

## Accessibility

- Glow never carries meaning on its own; it is off in high contrast and reduced-transparency modes.
