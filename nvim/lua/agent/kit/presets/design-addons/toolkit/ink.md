<!-- name: Ink -->
<!-- desc: the design in Ink terms: Box flex layout, one theme object, borderStyle, ink-testing-library frames -->
<!-- for: tui -->
<!-- default: js -->

## Toolkit

| Design | Ink |
| --- | --- |
| Color token | a key of one `theme` object (ANSI names `"blue"` when the theme inherits the terminal, hex for gradients) |
| Text style | a small component per role (`<Title>`, `<Muted>`, `<Key>`) wrapping `<Text color bold dimColor>` |
| Frame | `<Box borderStyle="round" borderColor={theme.border}>` (`single`, `double`, `bold`, `classic`) |
| Spacing | `padding`/`paddingX` inside, `margin`/`gap` between boxes |
| Layout | `<Box flexDirection="column">` with `flexGrow`, `justifyContent`, `alignItems` |
| Centering | a full-size `<Box width={columns} height={rows} justifyContent="center" alignItems="center">` |
| Size | `useStdout().stdout.columns/rows` (with a resize listener) |
| Grid / keypad | rows of fixed-`width` boxes; the focused one from `useFocus` gets `theme.focus` |
| Help bar | one line of `<Key>` + `<Muted>` pairs, truncated with `wrap="truncate-end"` |
| Motion | `ink-spinner` and a `setInterval` hook; stopped on unmount |

- Test frames with `ink-testing-library` (`lastFrame()`) at 80×24.

## Rules for agents

- Every color comes from the theme object; a component never names a color itself.
- Never pad with hand-counted spaces: widths come from flex and `width`.
