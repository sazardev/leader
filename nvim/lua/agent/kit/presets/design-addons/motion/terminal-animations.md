<!-- name: Terminal animations -->
<!-- desc: spinners, braille frames, progress bars and typewriter reveals within a 30-60 fps budget; off when not a TTY -->
<!-- for: tui -->
<!-- default: tui -->

## Motion

- Spinner frames: braille `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏` at 80 ms/frame (dots), or `◐ ◓ ◑ ◒`; ASCII fallback `| / - \`.
- Progress bars with sub-cell precision (`▏▎▍▌▋▊▉█`), percentage and ETA; indeterminate work uses a spinner, never a fake bar.
- Typewriter or fade-in reveals only for short headings (≤ 40 chars, ≤ 400 ms total).
- Redraw budget 30 fps for idle animation, 60 fps max while interacting; only changed cells are redrawn.

## Accessibility

- No animation when stdout is not a TTY, in `CI`, with `NO_COLOR`/`TERM=dumb`, or with the app's reduced-motion flag: print a single status line instead.

## Rules for agents

- Animations run on a ticker owned by the UI loop and stop when nothing is pending; never sleep in the render path.
