# Data and configuration formats

They have no leader menu; they rely on LSP, format on save (`<leader>fm`) and linters.

| Language | LSP | Format | Lint | Notes |
|---|---|---|---|---|
| **JSON** | `jsonls` + SchemaStore (automatic schemas for `package.json`, `tsconfig`, etc.) | `prettier` | `jsonlint` | |
| **YAML** | — | `prettier` | — | treesitter only |
| **TOML** | — | `prettier` | — | treesitter only |
| **Dockerfile** | `dockerls` and `docker_compose_language_service` | — | — | `lazydocker` available via `TermExec` |
| **Prisma** | `prismals` | via the LSP (`lsp_format = "fallback"`) | — | no formatter in conform |
| **YarnSpinner** (`*.yarn`) | — | — | `ysc` (optional) | see below |

## YarnSpinner

- `ftdetect/yarnspinner.vim`: `*.yarn` → filetype `yarnspinner`.
- `syntax/yarnspinner.vim`: highlighting for dialogue scripts.
- The **`ysc` linter is optional**: it is only enabled if it is on the PATH
  (`dotnet tool install -g yarn-spinner`, requires `dotnet`).
  Error format: `path(lnum,col): severity CODE: message`.
