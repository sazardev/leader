<!-- name: UnoCSS -->
<!-- desc: on-demand atomic CSS engine with presets, tokens in uno.config.ts -->
<!-- for: ui -->

## Stack

| Styling | UnoCSS (`unocss/vite`, `presetWind4` or `presetMini`), tokens in `uno.config.ts` | Generates only the utilities used, very small CSS, fast HMR |

## Project layout

```
uno.config.ts                  presets, theme tokens (colors, fonts, spacing), shortcuts
```

## Conventions

- Theme tokens in `uno.config.ts` mirror DESIGN.md; repeated utility groups become `shortcuts` with a role name (`btn-primary`).
- Icons through `presetIcons` (pure CSS icons, loaded on demand), not icon fonts.

## Rules for agents

- Never hardcode a color or size in a class: use a theme token, or add it to `uno.config.ts`.
- Add a shortcut instead of copying the same long class list into a third place.
- Never add a second CSS framework.
