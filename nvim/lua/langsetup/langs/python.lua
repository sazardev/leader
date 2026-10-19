-- Python setup (<leader>pS): ruff, pytest, .python-version, Docker (uv), CI, pre-commit, .editorconfig. Filled from
-- pyproject.toml (name, requires-python) or the folder's name.
local M = { name = "Python" }

---@param dir string
---@return string
function M.root(dir)
  return vim.fs.root(dir, { "pyproject.toml", "setup.py", "requirements.txt" }) or vim.fs.root(dir, ".git") or dir
end

---@param root string
---@return table<string, string>
function M.vars(root)
  local text = require("utils.project").read(root .. "/pyproject.toml") or ""
  local name = text:match '%[project%][^%[]-\nname%s*=%s*"([^"]+)"' or vim.fs.basename(root)
  local python = text:match 'requires%-python%s*=%s*"[>=~^]*%s*(%d+%.%d+)'
    or (require("utils.project").read(root .. "/.python-version") or ""):match "(%d+%.%d+)"
    or "3.12"
  return {
    name = name,
    package = (name:gsub("[%-%.]", "_")),
    python = python,
    pyver = python:gsub("%.", ""), -- ruff's target-version: py312
  }
end

M.topics = {
  { id = "ruff", key = "r", label = "ruff config", default = "standard", core = true, alts = { ".ruff.toml" } },
  { id = "pytest", key = "t", label = "pytest config", default = "standard" },
  { id = "pythonversion", key = "v", label = ".python-version", default = "pinned", core = true },
  { id = "docker", key = "d", label = "Dockerfile (uv)", default = "uv" },
  { id = "dockerignore", key = "i", label = ".dockerignore", default = "python" },
  { id = "ci", key = "c", label = "GitHub Actions CI", default = "github", alts = { ".github/workflows/ci.yaml" } },
  { id = "hooks", key = "h", label = "pre-commit hooks", default = "ruff" },
  { id = "editorconfig", key = "e", label = ".editorconfig", default = "python", core = true },
}

function M.hint(topic)
  if topic.id == "hooks" then
    return "run `pre-commit install` once (uv tool install pre-commit, or pipx)"
  elseif topic.id == "pytest" then
    return "pytest config in pytest.ini (a [tool.pytest.ini_options] in pyproject.toml works too)"
  end
end

return M
