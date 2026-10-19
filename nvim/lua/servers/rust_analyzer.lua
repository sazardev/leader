-- clippy as the check on save (its lints as diagnostics, not only the compiler's); proc macros expanded; the hints
-- that read like code (parameter names, chained types, closures' return types)
return {
  settings = {
    ["rust-analyzer"] = {
      check = { command = "clippy" },
      cargo = { buildScripts = { enable = true } },
      procMacro = { enable = true },
      inlayHints = {
        parameterHints = { enable = true },
        chainingHints = { enable = true },
        closureReturnTypeHints = { enable = "with_block" },
        typeHints = { hideClosureInitialization = true },
      },
    },
  },
}
