-- ── What the templates are filled with ───────────────────────────────────────
-- Read from the project, never asked: the module path and Go version from go.mod, the `main` package from where it really is
-- (`cmd/<name>/` or the root), the binary's name from that. The pure parts take text and names, `collect` reads the disk.
local M = {}

--- Folder names under `cmd/` that are a service before any other
local PREFERRED = { "api", "server", "app", "service", "web", "main" }

---@param gomod string
---@return string?
function M.module(gomod)
  return gomod:match "^module%s+([^%s]+)" or gomod:match "\nmodule%s+([^%s]+)"
end

--- `go 1.23.4` → `1.23` (what image tags and setup-go speak)
---@param gomod string
---@return string?
function M.go_version(gomod)
  local v = gomod:match "\ngo%s+(%d+%.%d+)" or gomod:match "^go%s+(%d+%.%d+)"
  return v
end

--- Where the program is: the root when it has a main.go, else the best folder of `cmd/`, else the root
---@param root_main boolean
---@param cmd string[] folders of cmd/ that hold a main.go
---@return string
function M.main_dir(root_main, cmd)
  if root_main then
    return "."
  end
  local sorted = vim.list_slice(cmd)
  table.sort(sorted)
  for _, name in ipairs(PREFERRED) do
    if vim.tbl_contains(sorted, name) then
      return "./cmd/" .. name
    end
  end
  if sorted[1] then
    return "./cmd/" .. sorted[1]
  end
  return "."
end

--- The binary's name: its cmd folder, else the last element of the module path (not a `/v2`), else the folder's
---@param module string?
---@param main string
---@param folder string
---@return string
function M.binary(module, main, folder)
  local name = main ~= "." and vim.fs.basename(main) or nil
  if not name and module then
    local parts = vim.split(module, "/", { plain = true })
    name = parts[#parts]
    if name:match "^v%d+$" and parts[#parts - 1] then
      name = parts[#parts - 1]
    end
  end
  name = (name or folder):gsub("[^%w._-]", "-")
  return name ~= "" and name or "app"
end

---@param path string
---@return string?
local function read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read "*a"
  f:close()
  return text
end

---@class SetupVars
---@field module string
---@field go string
---@field main string
---@field binary string

--- Everything the templates use, for the module at `root`
---@param root string
---@return SetupVars
function M.collect(root)
  local gomod = read(root .. "/go.mod") or ""
  local module = M.module(gomod)
  local cmd = {}
  for name, kind in vim.fs.dir(root .. "/cmd") do
    if kind == "directory" and vim.uv.fs_stat(("%s/cmd/%s/main.go"):format(root, name)) then
      cmd[#cmd + 1] = name
    end
  end
  local main = M.main_dir(vim.uv.fs_stat(root .. "/main.go") ~= nil, cmd)
  local folder = vim.fs.basename(root)
  local go = M.go_version(gomod)
  if not go then
    go = (vim.fn.executable "go" == 1 and vim.fn.system({ "go", "env", "GOVERSION" }):match "go(%d+%.%d+)") or "1.24"
  end
  return { module = module or folder, go = go, main = main, binary = M.binary(module, main, folder) }
end

--- Fills `{{name}}`. Returns the text and the placeholders nobody knew
---@param text string
---@param vars table<string, string>
---@return string text, string[] unknown
function M.render(text, vars)
  local unknown = {}
  local out = text:gsub("{{(%w+)}}", function(name)
    if vars[name] then
      return vars[name]
    end
    unknown[#unknown + 1] = name
    return nil
  end)
  return out, unknown
end

return M
