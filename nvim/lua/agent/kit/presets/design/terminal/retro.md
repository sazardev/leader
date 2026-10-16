<!-- name: Retro CRT -->
<!-- desc: phosphor green or amber monochrome, DOS/BBS double lines, blinking cursor, typewriter reveal -->

# DESIGN.md: Retro CRT

An 80s terminal aesthetic: a monochrome phosphor (green P1 or amber P3) on black, DOS/BBS double-line frames, a block
cursor that blinks, text that types itself in. Nostalgic but usable: every effect has a switch and a fallback.

## Principles

- **One phosphor**: everything is one hue in a few intensities; no second color except for danger (approx. still in phosphor tones).
- **Frames from the BBS era**: CP437-style double lines and shaded blocks.
- **Text arrives**: reveals and blinking cursors make the machine feel alive, briefly.
- **Readable first**: effects are short and skippable; working screens stay calm.
- **Honest fallback**: without truecolor the phosphor maps to ANSI green/yellow.

## Color

| Token | Green phosphor | Amber phosphor | ANSI 16 fallback | Use |
| --- | --- | --- | --- | --- |
| `bg` | `#0A0F0A` (approx.) | `#120C04` (approx.) | default bg | Screen (painted only if the app owns the full screen) |
| `fg` | `#33FF66` | `#FFB000` | 2 green / 3 yellow | Text |
| `fg-bright` | `#B6FFC8` | `#FFD27A` | 10 / 11 (bright) | Titles, selection text |
| `fg-dim` | `#1C8C3A` | `#8C6100` | 2 / 3 dim | Secondary text, borders |
| `selection` | reverse video | reverse video | SGR 7 | Selected row |
| `danger` | `#FF5544` (approx.) | `#FF5544` (approx.) | 1 red | Errors (only exception to the single hue) |

- 256-color: green 46/34/22, amber 214/172/130 (approx.).
- The palette is a choice (green or amber), set once per app; never mix both.

## Typography

| Role | Style | Use |
| --- | --- | --- |
| Body | `fg` | Text |
| Title | `fg-bright` bold, ALL CAPS | Screen and panel titles |
| Secondary | `fg-dim` | Hints, metadata |
| Prompt | `C:\>` or `> ` in `fg-bright` | Inputs |
| Cursor | block `█` blinking | Input position |

- Recommended fonts (user side): IBM Plex Mono, "Px437" IBM VGA fonts from the Ultimate Oldschool PC Font Pack (approx.), any monospace works.

## Spacing and layout

- Unit = one cell; classic 80×25 frame centered on larger terminals (letterboxed with `bg`), or fluid from 80×24.
- "Scanline" spacing: one blank row between sections, giving the striped CRT rhythm; never more than one.
- Menus as numbered lists (BBS style) or a top menu bar.

## Shape and elevation

| Token | Glyphs | Use |
| --- | --- | --- |
| frame-double | `╔═╗║╚╝╠╣╦╩╬` | Screens, dialogs |
| frame-single | `┌─┐│└┘` | Inner panels |
| shade | `░▒▓` | Shadows, progress fill, decorative bands |
| separator | `═` or `─` | Sections |

- Elevation: dialogs with double frame and a `▒` shadow one cell right and down.

## Motion

| Token | Value | Use |
| --- | --- | --- |
| cursor-blink | 530 ms on / 530 ms off | Input cursor |
| typewriter | 8–15 ms per character, max 800 ms per block | Splash, messages from the "machine" |
| boot | 3–6 lines of fake POST/boot text, ≤ 1.5 s, skippable | Splash only |
| spinner | `|/-\` 100 ms | Activity |
| frame-budget | 30 fps | Reveal effects |

- Any key completes a reveal instantly. Reduced motion: no typewriter, no boot, cursor steady.

## Components

- **Splash**: boot lines + the app name in a double frame, one `PRESS ANY KEY` line.
- **Menu**: numbered BBS menu (`[1] Messages  [2] Files  [Q] Quit`) or top bar.
- **Lists/tables**: headers in `fg-bright`, rows in `fg`, selected row reverse video.
- **Status bar**: bottom row in reverse video with time and mode.
- **Prompts**: `> ` + blinking block cursor.
- **Progress**: `[▓▓▓▓▓▓░░░░] 60%`.
- **Dialogs**: double frame, `▒` shadow, `[ OK ]`.
- **Empty/loading/error**: `NO RECORDS FOUND.` / spinner + `LOADING…` / `ERROR: <cause>` in `danger`, each typed in.

## Accessibility

- Contrast: phosphor on black ≥ 7:1 for `fg` (approx.); `fg-dim` only for non-essential text.
- `NO_COLOR`: monochrome terminal default colors, reverse video for selection; effects stay optional.
- Reduced motion and plain mode disable typewriter, boot and blinking.
- Errors use words (`ERROR:`), not only the red exception.

## Rules for agents

- One palette constant (green or amber) chosen in config; views use roles only.
- Effects (typewriter, boot, blink) live in one `fx` module with a global switch; never inline sleeps in views.
- Bubble Tea: reveals as `tea.Tick` commands updating a revealed-length field; Lip Gloss `DoubleBorder()`. Ratatui: tick events advance the reveal; `BorderType::Double`.
- Never block input during an effect; any key finishes it.
- Test with truecolor, 256 and 16 colors, and with `NO_COLOR=1`.
