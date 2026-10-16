<!-- name: ASCII art -->
<!-- desc: character ramps, figlet banners, truecolor gradients across glyphs, dithering, box art, with clean fallbacks -->

# DESIGN.md: ASCII art

A terminal design where characters are the paint: density ramps for shading, figlet banners for identity, per-character
truecolor gradients, dithering for images and box art for frames. The art lives in a few places that earn it (splash, headers,
empty states, about); the working screens stay readable. Everything degrades: truecolor → 256 → 16 colors → no color, and
Unicode → pure ASCII.

## Principles

- **Characters are pixels with meaning**: choose glyphs by density and shape, not by font accident.
- **Art earns its place**: banners and pictures appear on splash, headers, empty and about screens; never between the user and the data.
- **Gradients carry mood, not information**: color sweeps decorate; meaning is always in text too.
- **Width is sacred**: art never exceeds the terminal width; it scales, swaps to a smaller font, or disappears.
- **Every layer degrades**: truecolor art still reads as monochrome ASCII.

## Color

| Token | ANSI 16 | 256 | Truecolor | Use |
| --- | --- | --- | --- | --- |
| `fg` | default fg | default | default | Text |
| `muted` | 8 | 244 | `#808080` | Secondary text, low-density ramp chars |
| `gradient-start` | 5 (magenta) | 199 | `#FF4FD8` (approx.) | First stop of banners |
| `gradient-mid` | 4 (blue) | 63 | `#7A5CFF` (approx.) | Middle stop |
| `gradient-end` | 6 (cyan) | 51 | `#22D3EE` (approx.) | Last stop |
| `accent` | 6 (cyan) | 45 | `#22D3EE` | Focus, keys |
| `success` | 2 | 114 | `#4ADE80` | Done |
| `warning` | 3 | 221 | `#FACC15` | Attention |
| `danger` | 1 | 203 | `#F87171` | Errors |

Gradients:
- **Directions**: horizontal (by column), vertical (by row), diagonal (by `col + 2*row`, cells are ~2:1), radial (by distance from center, aspect-corrected).
- **Interpolation**: in OKLCH (perceptually even; fall back to HSL when no OKLCH library), 2–4 stops, color per character (not per line).
- **Fallbacks**: 256-color → nearest of the 6×6×6 cube per character; ANSI 16 → split the art into 2–3 bands with `gradient-start`/`mid`/`end`; `NO_COLOR` → no color, the ramp alone.
- Only non-space characters get color; spaces stay the terminal background.

## Typography

| Role | Glyphs | Use |
| --- | --- | --- |
| Ramp (short) | `" .:-=+*#%@"` | Shading, small images, density |
| Ramp (long, 70) | `` $@B%8&WM#*oahkbdpqwmZO0QLCJUYXzcvunxrjft/\|()1{}[]?-_+~<>i!lI;:,"^`'. `` (dark → light) | Detailed image-to-ASCII |
| Blocks | `░▒▓█ ▀▄▌▐` | Smooth shading when Unicode is available |
| Banner | figlet/toilet fonts: `standard` (body), `ANSI Shadow` / `Big` (splash), `small` (narrow) | Titles |
| Box art | `+-|` (ASCII), `┌─┐` `╔═╗` `╭─╮` (Unicode) | Frames |
| Text | default weight; bold for titles; dim for hints | Everything else |

- Banner widths: `ANSI Shadow` ≈ 7–8 cols/letter, `standard` ≈ 5–6, `small` ≈ 4 (approx.). Pick the largest font that fits the width minus 4 cells, else plain bold text.
- Ramps run dark → light for dark terminals; reverse them on light terminals (detect with `COLORFGBG` or a setting).

## Spacing and layout

- Unit = one cell; art blocks get 1 empty row above and below, and are centered or left-aligned to the content column.
- Minimum terminal 80×24. Art rules: splash ≤ 70% of the height; header banners ≤ 6 rows; below 60 columns banners become plain bold text.
- Image-to-ASCII: target width = available columns, height = `width * (image_h / image_w) * 0.5` (cells are about twice as tall as wide).
- Content screens: art never above the fold of a working view; a 1-row gradient title is the maximum there.

## Shape and elevation

| Token | ASCII | Unicode | Use |
| --- | --- | --- | --- |
| frame-light | `+-+` `|` | `┌─┐│` | Panels |
| frame-heavy | `#=#` | `╔═╗║` | Dialogs, splash frame |
| frame-round | — | `╭─╮│` | Friendly panels |
| shadow | `▒`/`░` one cell right and below | same | Dialog depth on splash screens |

- Elevation by framing and a 1-cell shade shadow (`░`) to the right and bottom of dialogs; never color-filled backgrounds.

## Motion

| Token | Value | Use |
| --- | --- | --- |
| frame-budget | 30 fps (33 ms) for art, 12 fps for spinners | Animation cost |
| gradient-shift | stops move 1 column per frame, loop 2–4 s | Living banners (splash only) |
| reveal | per character, 2–4 ms each, max 600 ms total | Typewriter banner on splash |
| ramp-fade | step through the ramp in 6 frames | Appear/disappear of art |
| spinner | `|/-\` (ASCII) or `◐◓◑◒` | Activity |

- Animations run only on splash/about/empty screens and stop when input arrives; reduced motion shows the final frame at once.

## Components

- **Splash**: figlet banner with a diagonal gradient, version and one hint line; any key dismisses it; never shown twice per session.
- **Header**: small font or a single bold gradient line with the app name; collapses to plain text under 60 columns.
- **Empty states**: a small ASCII picture (≤ 8 rows) + one sentence + the key to act.
- **Image viewer**: dithered ASCII (ordered 4×4 Bayer for animation stability, Floyd–Steinberg for stills) using the long ramp; truecolor per character when available.
- **Lists/tables/panes/status bar/help bar**: plain and readable; art never inside them.
- **Progress**: ramp-filled bar (`[####=====---]` or `▏▎▍▌▋▊▉█`) with a percentage.
- **Dialogs**: heavy frame + shade shadow; buttons as `[ OK ]` with the focused one in reverse video.
- **Errors**: `danger` text with the cause and the next step; no art.

## Accessibility

- `NO_COLOR`/`TERM=dumb`: art keeps its shape without color; gradients off.
- Screen readers and `--plain`: banners replaced by the app name as text, images by an alt line, art skipped entirely.
- Art never conveys required information; every picture has a text equivalent.
- Reduced motion: no gradient shift, no typewriter; static final frames.
- Contrast of text over nothing (terminal background) only; never put text on top of art.

## Rules for agents

- Keep art in files (`assets/art/*.txt`, banners generated at build or with a figlet library), never as long string literals in views.
- One `gradient` helper (stops, direction, color depth) and one `ramp` helper (value 0–1 → glyph); views call them.
- Go: `github.com/common-nighthawk/go-figure` or embedded figlet fonts + Lip Gloss per-character styles; Rust: `figlet-rs` + Ratatui `Span`s per character (approx. library choices: verify before adding).
- Always measure art width with display width (runes, not bytes) and drop to the next smaller variant when it does not fit.
- Provide ASCII-only and no-color variants for every piece of art and test them (`LANG=C`, `NO_COLOR=1`).
- Animations stop on the first key press and never run on working screens.
