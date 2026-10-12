# Lua (la propia config)

Filetype: `lua`.

## Herramientas

| Qué | Con |
|---|---|
| LSP | `lua_ls` (NvChad lo habilita) |
| Formato (al guardar y `<leader>fm`) | `stylua` (se instala siempre, también en modo ligero) |
| Treesitter | `lua`, `vim`, `vimdoc` |
| Extra | **lazydev**: tipos de la API de Neovim y completado de `require()` / módulos de plugins |

## Completado

En Lua las fuentes de blink son: `lazydev`, LSP, path, snippets, buffer (lazydev con prioridad).

## Comandos útiles

| Comando | Acción |
|---|---|
| `:luafile %` | ejecutar el archivo actual |
| `:lua =expr` | evaluar e imprimir una expresión |
| `:Lazy sync` | instalar/actualizar plugins (el auto-reload de `git pull` no lo hace) |

## Auto-reload

Tras `git pull`, el hook `.githooks/post-merge` deja un marcador y, al abrir nvim (`UIEnter`),
`core/autocmds/reload.lua` corre `luafile $MYVIMRC`. Activar una vez por clon:

```sh
git config core.hooksPath .githooks
```

Recarga Lua, pero **no** instala/quita plugins ni parsers de treesitter.
