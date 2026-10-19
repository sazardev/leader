-- The project's virtual environment is the interpreter (the imports it installed resolve): `.venv` or `venv` at the root
-- (uv, poetry with in-project venvs, python -m venv), else whatever python is on PATH. Type checking "standard": the
-- server's own "recommended" flags most untyped code; a pyproject/pyrightconfig setting still wins.
local function venv_python(root)
  for _, dir in ipairs { ".venv", "venv" } do
    for _, bin in ipairs { "/bin/python", "/Scripts/python.exe" } do
      local path = root .. "/" .. dir .. bin
      if vim.fn.executable(path) == 1 then
        return path
      end
    end
  end
end

return {
  settings = {
    basedpyright = {
      analysis = {
        typeCheckingMode = "standard",
        diagnosticMode = "openFilesOnly",
        inlayHints = { callArgumentNames = true, variableTypes = false, functionReturnTypes = true },
      },
    },
  },
  before_init = function(_, config)
    local python = config.root_dir and venv_python(config.root_dir)
    if python then
      config.settings = vim.tbl_deep_extend("force", config.settings or {}, { python = { pythonPath = python } })
    end
  end,
}
