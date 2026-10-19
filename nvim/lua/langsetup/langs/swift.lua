-- Swift setup (<leader>iS): swift-format, swiftlint, Docker, CI, .editorconfig. Filled from Package.swift (package
-- name, tools version).
local M = { name = "Swift" }

---@param dir string
---@return string
function M.root(dir)
  return vim.fs.root(dir, "Package.swift") or vim.fs.root(dir, ".git") or dir
end

---@param root string
---@return table<string, string>
function M.vars(root)
  local text = require("utils.project").read(root .. "/Package.swift") or ""
  local name = text:match 'Package%(%s*name:%s*"([^"]+)"' or vim.fs.basename(root)
  return {
    name = name,
    binary = name,
    swift = text:match "swift%-tools%-version:%s*(%d+%.%d+)" or "6.0",
  }
end

M.topics = {
  { id = "swiftformat", key = "f", label = "swift-format config", default = "standard", core = true },
  { id = "swiftlint", key = "l", label = "SwiftLint config", default = "standard" },
  { id = "docker", key = "d", label = "Dockerfile", default = "server" },
  { id = "dockerignore", key = "i", label = ".dockerignore", default = "swift" },
  { id = "ci", key = "c", label = "GitHub Actions CI", default = "github", alts = { ".github/workflows/ci.yaml" } },
  { id = "editorconfig", key = "e", label = ".editorconfig", default = "swift", core = true },
}

return M
