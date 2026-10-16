<!-- name: Synthwave -->
<!-- desc: neon TUI: magenta→cyan truecolor gradients, glow via bright colors, sun and grid art, 16-color fallback -->

# DESIGN.md: Synthwave

An 80s neon terminal style: deep purple-black, magenta-to-cyan truecolor gradients, "glow" faked with bold bright colors,
a retro sun and perspective grid for splash screens. Expressive but usable: the working screens stay readable and every
effect degrades to 16 colors.

## Principles

- **Neon on the edges**: gradients and glow on titles, borders and focus; content stays plain `fg`.
- **Glow is brightness, not blur**: bold + bright variants + a darker shadow row.
- **One splash, many calm screens**: the sun and grid live on the splash/about screen only.
- **Degrade with dignity**: 256 and 16 colors keep the magenta/cyan identity.
- **Readable first**: body text never sits on a gradient background.

## Color

| Token | ANSI 16 | 256 | Truecolor | Use |
| --- | --- | --- | --- | --- |
| `bg` | default bg | default | `#1A0B2E` (only if the app paints its own, opt-in) | Background |
| `fg` | default fg | default | `#F2E9FF` | Text |
| `muted` | 8 | 103 | `#8A7BAA` | Labels, hints |
| `neon-magenta` | 13 (bright magenta) | 199 | `#FF2BD6` | Gradient start, titles |
| `neon-violet` | 5 (magenta) | 135 | `#A64DFF` | Gradient middle |
| `neon-cyan` | 14 (bright cyan) | 51 | `#2DE2E6` | Gradient end, focus |
| `neon-yellow` | 11 (bright yellow) | 221 | `#FFD319` | Sun top, highlights |
| `neon-orange` | 9 (bright red) | 209 | `#FF8C42` | Sun bottom |
| `success` | 10 (bright green) | 84 | `#39FF88` | States |
| `danger` | 9 (bright red) | 197 | `#FF3864` | Errors |

- Gradients interpolate in OKLCH per character across magenta → violet → cyan; 256: nearest per character; 16: three bands (13, 5, 14).
- `NO_COLOR`: no color; titles keep their block letters, focus uses reverse video.

## Typography

| Role | Glyphs / style | Use |
| --- | --- | --- |
| splash title | figlet `ANSI Shadow` / block letters, gradient per character, bold | Splash |
| title | bold, gradient across the word | Pane titles |
| glow | bold bright color + the row below repeated in `neon-violet` dim (`▀` shadow) | Splash title only |
| text | default `fg` | Content |
| hint | `muted` | Help bar |
| key | bold `neon-cyan` | Keys in help |

## Spacing and layout

- Minimum 80×24; splash needs 80×20 for sun + grid, otherwise shows the title alone.
- Panes with 1-cell padding; a 1-row help bar at the bottom.
- Sun: 7 rows of `█` with horizontal gaps (`▀▀▀` stripes) shading yellow → orange; grid: 6 rows of `╱ │ ╲` perspective lines in `neon-violet` below a horizon `─` in `neon-magenta`.

## Shape and elevation

| Token | Value | Use |
| --- | --- | --- |
| `border` | rounded `╭─╮│╰─╯`, gradient along the top edge | Panels |
| `focus-border` | heavy `┏━┓┃┗┛` in `neon-cyan` | Focused panel |
| `shadow` | `▀`/`▄` row in dim `neon-violet` under floats | Floating dialogs |
| `selection` | `neon-violet` background + `fg` bold (256/truecolor); reverse in 16 | Selected row |

## Motion

| Token | Value |
| --- | --- |
| `fps` | 30 max |
| `gradient-shift` | 1 step per frame on the splash title only |
| `grid-scroll` | grid lines move 1 row per 120ms toward the viewer (splash) |
| `typewriter` | 12ms per character for the tagline |

- Working screens never animate except the spinner; splash animations stop after 3s or on any key.
- Reduced motion (`REDUCED_MOTION=1` or a setting): static splash.

## Components

- **Splash**: block title with gradient and glow, tagline (typewriter), sun + grid, "press any key".
- **Panels and lists**: rounded borders, gradient top edge, selection as described.
- **Help bar**: keys in `neon-cyan`, descriptions `muted`.
- **Progress**: bar of `━` cells with gradient fill; spinner `◜◠◝◞◡◟` in `neon-magenta`.
- **States**: empty (small sun glyph + one line), loading (spinner + text), error (`danger` text in a bordered note).

## Accessibility

- Content text is plain `fg`, contrast ≥ 4.5:1 on the terminal background; neon colors are for chrome and short labels.
- Every animation stops on input and respects reduced motion; no flashing faster than 3 per second.
- Plain mode (not a TTY or `--plain`): no art, no colors, text only.
- Focus visible without color (heavy border).

## Rules for agents

- Gradients and glow only on titles, borders, focus and the splash; never on body text or table cells.
- Detect color depth (`COLORTERM`, terminfo) once at startup and pick truecolor / 256 / 16 palettes from the tokens.
- One theme module owns every style (Lip Gloss / Ratatui `Style`); no escapes in views.
- The splash is skippable and shown at most once per session.
- Keep animations under the fps budget and off when output is not a TTY.
