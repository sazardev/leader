-- TypeScript / JavaScript: vtsls for types, eslint's server where the project has an eslint config, biome where it has
-- a biome.json (then it formats too; prettier otherwise). Menu: package.json scripts, tests in the editor (vitest,
-- jest, bun), typecheck to the quickfix list, imports, project setup.
local fmt = { "biome", "prettier", stop_after_first = true }
local eslint = { "eslint_d" }

return {
  filetypes = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
  treesitter = { "javascript", "typescript", "tsx", "jsdoc" },
  lsp = { "vtsls", "eslint", "biome" },
  mason = { full = { "prettier", "eslint_d", "vtsls", "eslint-lsp", "biome" } },
  formatters = {
    javascript = fmt,
    typescript = fmt,
    javascriptreact = fmt,
    typescriptreact = fmt,
  },
  -- biome only where the project uses it (a biome.json): without one, prettier formats
  formatter_options = { biome = { require_cwd = true } },
  -- full mode: the eslint server reports the same, live and on unsaved text, so eslint_d (a second Node process that
  -- only lints the file on disk) runs only in light mode, where no server is resident
  linters_light = {
    javascript = eslint,
    typescript = eslint,
    javascriptreact = eslint,
    typescriptreact = eslint,
  },
  menu = {
    name = "TypeScript / JavaScript",
    prefix = "t",
    maps = require "languages.actions.typescript",
    groups = { S = "setup" },
  },
}
