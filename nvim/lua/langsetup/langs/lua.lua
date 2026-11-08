-- Lua setup (<leader>lS): stylua, selene, .luarc.json, .editorconfig, CI. Filled from the folder's name.
local M = { name = "Lua" }

---@param dir string
---@return string
function M.root(dir)
  return vim.fs.root(dir, function(name)
    return name == ".luarc.json" or name == "stylua.toml" or name == "selene.toml" or name == "init.lua"
  end) or vim.fs.root(dir, ".git") or dir
end

---@param root string
---@return table<string, string>
function M.vars(root)
  return { name = vim.fs.basename(root) }
end

M.topics = {
  { id = "stylua", key = "s", label = "stylua.toml", default = "standard", core = true },
  { id = "selene", key = "l", label = "selene.toml", default = "standard" },
  { id = "luarc", key = "r", label = ".luarc.json", default = "standard", core = true },
  { id = "editorconfig", key = "e", label = ".editorconfig", default = "lua", core = true },
  { id = "ci", key = "c", label = "GitHub Actions CI", default = "github", alts = { ".github/workflows/ci.yaml" } },
}

return M
