# Formatos de datos y configuración

No tienen menú de leader; se apoyan en LSP, formato al guardar (`<leader>fm`) y linters.

| Lenguaje | LSP | Formato | Lint | Notas |
|---|---|---|---|---|
| **JSON** | `jsonls` + SchemaStore (schemas automáticos para `package.json`, `tsconfig`, etc.) | `prettier` | `jsonlint` | |
| **YAML** | — | `prettier` | — | solo treesitter |
| **TOML** | — | `prettier` | — | solo treesitter |
| **Dockerfile** | `dockerls` y `docker_compose_language_service` | — | — | `lazydocker` disponible vía `TermExec` |
| **Prisma** | `prismals` | por el LSP (`lsp_format = "fallback"`) | — | sin formatter en conform |
| **YarnSpinner** (`*.yarn`) | — | — | `ysc` (opcional) | ver abajo |

## YarnSpinner

- `ftdetect/yarnspinner.vim`: `*.yarn` → filetype `yarnspinner`.
- `syntax/yarnspinner.vim`: resaltado para guiones de diálogo.
- El linter **`ysc` es opcional**: solo se activa si está en el PATH
  (`dotnet tool install -g yarn-spinner`, requiere `dotnet`).
  Formato de error: `path(lnum,col): severity CODE: message`.

