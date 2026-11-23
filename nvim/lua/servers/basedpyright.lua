-- The project's virtual environment is the interpreter (the imports it installed resolve): `.venv` or `venv` at the root
-- (uv, poetry with in-project venvs, python -m venv), else whatever python is on PATH. Type checking "standard": the
-- server's own "recommended" flags most untyped code; a pyproject/pyrightconfig setting still wins.
local function venv(root)
  if type(root) ~= "string" then
    return
  end
  for _, dir in ipairs { ".venv", "venv" } do
    for _, bin in ipairs { "/bin/python", "/Scripts/python.exe" } do
      local path = root .. "/" .. dir .. bin
      if vim.fn.executable(path) == 1 then
        return path, dir
      end
    end
  end
end

local M = {
  settings = {
    basedpyright = {
      analysis = {
        typeCheckingMode = "standard",
        diagnosticMode = "openFilesOnly",
        -- Auto-import: suggestions for local modules, the stdlib and modules the server already knows.
        -- Third-party packages still have to be installed in the project's .venv (uv add).
        autoImportCompletions = true,
        autoSearchPaths = true,
        useLibraryCodeForTypes = true,
        inlayHints = { callArgumentNames = true, variableTypes = true, functionReturnTypes = true },
      },
    },
  },
  -- Inlay hints on by default for Python: inferred variable types (`x: list[int]`), call-argument
  -- names and unannotated return types. <leader>ph toggles them (languages/actions/python.lua).
  on_attach = function(_, bufnr)
    vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
  end,
  before_init = function(_, config)
    local python, dir = venv(config.root_dir)
    if python then
      -- venvPath + venv (not just pythonPath): basedpyright then excludes the venv from the workspace instead of
      -- indexing its ~2700 .py files, which shows up as ~500 MB of RSS and a slower first analysis.
      config.settings = vim.tbl_deep_extend("force", config.settings or {}, {
        python = { pythonPath = python, venvPath = config.root_dir, venv = dir },
      })
    end
  end,
}

require("servers.basedpyright_prewarm").setup()

return M
