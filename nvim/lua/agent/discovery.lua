-- ── Project code discovery (generic) ─────────────────────────────────────────
-- Utilities shared by the architecture levels (repository, service...): search with ripgrep and
-- read a type definition with treesitter, in any language and without depending on what the folders are called.
local scopes = require "agent.context.scopes"

local M = {}

local SKIP = vim.list_extend(
  { "-g", "!*_test.*", "-g", "!*.test.*", "-g", "!*.spec.*", "-g", "!**/node_modules/**", "-g", "!**/vendor/**" },
  require("utils.generated").rg_excludes()
)

---@param ext string
---@return string? lang
function M.lang_of(path, ext)
  local ft = vim.filetype.match { filename = path }
  return ft and vim.treesitter.language.get_lang(ft) or nil
end

--- Searches with ripgrep; `cb` receives { { path, line, text } } (empty if there is no rg or no results)
---@param root string
---@param regex string
---@param extra string[]?
---@param cb fun(hits: { path: string, line: integer, text: string }[])
function M.search(root, regex, extra, cb)
  if vim.fn.executable "rg" ~= 1 then
    return cb {}
  end
  local cmd = { "rg", "--no-heading", "-n", "--max-count", "3", "-e", regex }
  vim.list_extend(cmd, SKIP)
  vim.list_extend(cmd, extra or {})
  cmd[#cmd + 1] = root
  vim.system(cmd, { text = true }, function(out)
    vim.schedule(function()
      local hits = {}
      for line in (out.stdout or ""):gmatch "[^\r\n]+" do
        local path, n, text = line:match "^(.-):(%d+):(.*)$"
        if path then
          hits[#hits + 1] = { path = path, line = tonumber(n), text = text }
        end
      end
      cb(hits)
    end)
  end)
end

---@class AgentFoundType
---@field name string
---@field path string
---@field line integer
---@field lines string[]

--- Definition (with its associated constants) of a project type by name, or nil if it is not from here
---@param root string
---@param name string
---@param ext string
---@param cb fun(found: AgentFoundType?)
function M.find_type(root, name, ext, cb)
  local regex = ("(type\\s+%s\\s+(struct|interface)\\b|(class|struct|interface|enum|trait)\\s+%s\\b)"):format(
    name,
    name
  )
  M.search(root, regex, ext ~= "" and { "-g", "*." .. ext } or nil, function(hits)
    local hit = hits[1]
    if not hit or vim.fn.getfsize(hit.path) > 400000 then
      return cb(nil)
    end
    local text = table.concat(vim.fn.readfile(hit.path), "\n")
    local lang = M.lang_of(hit.path, hit.path:match "%.([%w]+)$" or "")
    local all = vim.split(text, "\n", { plain = true })
    local first, last = hit.line, math.min(hit.line + 25, #all)
    local lines
    if lang then
      for _, d in ipairs(scopes.type_declarations(text, lang)) do
        if d.name == name and not d.kind:find("impl", 1, true) then
          first, last = d.first, math.min(d.last, d.first + 30)
          break
        end
      end
      lines = vim.list_slice(all, first, last)
      -- the values of an enum-like type (Pending, Confirmed...) live in a separate `const (...)`
      for _, c in ipairs(scopes.constants_of(text, lang, name)) do
        if c.last - c.first < 15 then
          lines[#lines + 1] = ""
          vim.list_extend(lines, vim.list_slice(all, c.first, c.last))
        end
      end
    else
      lines = vim.list_slice(all, first, last)
    end
    cb { name = name, path = hit.path, line = first, lines = lines }
  end)
end

--- Concrete types whose name contains the port's (`PostgresOrderRepository` for `OrderRepository`)
---@param root string
---@param port string port name
---@param ext string
---@param cb fun(found: { name: string, path: string, line: integer }[])
function M.implementations(root, port, ext, cb)
  local base = port:gsub("^I%f[%u]", "")
  local regex = ("(type\\s+\\w*%s\\w*\\s+struct|class\\s+\\w*%s\\w*|struct\\s+\\w*%s\\w*)"):format(base, base, base)
  M.search(root, regex, ext ~= "" and { "-g", "*." .. ext } or nil, function(hits)
    local out = {}
    for _, h in ipairs(hits) do
      local name = h.text:match "type%s+([%w_]+)" or h.text:match "class%s+([%w_]+)" or h.text:match "struct%s+([%w_]+)"
      if name and name ~= port and not h.text:find "interface" and not h.text:find "abstract" then
        out[#out + 1] = { name = name, path = h.path, line = h.line }
      end
    end
    cb(out)
  end)
end

--- Is `name` used in any other non-test file (e.g. wired in the composition root)?
---@param root string
---@param name string
---@param own_path string file that defines it (does not count)
---@param cb fun(used: boolean?) nil if there is no ripgrep
function M.referenced_elsewhere(root, name, own_path, cb)
  if vim.fn.executable "rg" ~= 1 then
    return cb(nil)
  end
  vim.system({
    "rg",
    "-l",
    "-w",
    "--glob",
    "!*_test.*",
    "--glob",
    "!*.test.*",
    "--glob",
    "!*.spec.*",
    "--glob",
    "!**/test/**",
    "--glob",
    "!**/tests/**",
    "--",
    name,
    root,
  }, { text = true }, function(out) -- stylua: ignore
    vim.schedule(function()
      for file in (out.stdout or ""):gmatch "[^\r\n]+" do
        if file ~= own_path then
          return cb(true)
        end
      end
      cb(false)
    end)
  end)
end

---@param path string
---@param root string
---@return string path relative to the project
function M.rel(path, root)
  return path:sub(1, #root + 1) == root .. "/" and path:sub(#root + 2) or path
end

return M
