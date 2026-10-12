# Web: HTML, CSS, Tailwind, Astro

## HTML
| Qué | Con |
|---|---|
| LSP | `html` y `emmet_ls` (expande abreviaturas Emmet: `ul>li*3` + completado) |
| Formato (al guardar y `<leader>fm`) | `prettier` |
| Extra | `nvim-ts-autotag`: al escribir `<div>` cierra `</div>` y renombra la pareja |

## CSS / SCSS / Less
| Qué | Con |
|---|---|
| LSP | `cssls` |
| Formato | `prettier` |
| Preview de colores | nvim-highlight-colors (hex, rgb, Tailwind) |

### Menú `<leader>s` (solo en css, scss, less)
Las teclas están en [`CHEATSHEET.md`](../../CHEATSHEET.md) (generado; no se duplican aquí).

## Tailwind
- Servidor `tailwindcss` (transversal: no tiene filetype propio, aplica donde el proyecto use Tailwind).
- Autocompletado de clases, y preview de colores Tailwind en el buffer.

## Astro
| Qué | Con |
|---|---|
| LSP | `astro-language-server` |
| Formato | `prettier` — **requiere `prettier-plugin-astro`** en el proyecto (`node_modules`) o instalado global; Mason solo instala `prettier` |

