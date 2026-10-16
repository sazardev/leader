<!-- name: Inherit the terminal -->
<!-- desc: the user's terminal palette is the theme: ANSI 16 roles, default fg/bg, NO_COLOR and dumb terminals respected -->
<!-- for: tui -->
<!-- default: tui -->

## Principles

- **The terminal decides**: the app looks native in every theme the user already chose (Gruvbox, Catppuccin, Solarized…), light or dark, because it never paints its own background.

## Color

- Colors are **ANSI roles, not hex**: default foreground/background for text, `8`/bright black for muted, `1` red for danger, `2` green for success, `3` yellow for warning, `4` blue for accent, `5` magenta for highlights, `6` cyan for links/info.
- Never set a background on the whole screen; selections use reverse video (`SGR 7`) or the accent as background with the default background as text.
- Truecolor (`COLORTERM=truecolor`) only for gradients and charts, always with an ANSI 16 fallback; 256-color in between.
- `NO_COLOR` set or `TERM=dumb` → no colors at all, hierarchy by bold, dim, underline and spacing alone; not a TTY → plain text.

## Rules for agents

- Read colors through one theme module that maps roles to ANSI indexes; never write an escape sequence or a hex value in a view.
- Test every screen with a light and a dark terminal theme and with `NO_COLOR=1`.
