-- ── File operations: path helpers (pure) ─────────────────────────────────────
-- What you type in the modals ("src/ui/menu.go; docs/") turned into paths, and the names a copy or a trash entry gets.
-- No file system access: tested in scripts/test-files.lua.
local M = {}

---@class FilesName
---@field name string   as typed, without the trailing slash
---@field dir boolean   it ended with "/": a folder

--- "a.go; b/c.go; d/" → { a.go, b/c.go, d (dir) }. Several are separated by ";"
---@param input string
---@return FilesName[]
function M.split(input)
  local out = {}
  for part in (input or ""):gmatch "[^;]+" do
    local name = vim.trim(part)
    if name ~= "" then
      local dir = name:sub(-1) == "/"
      name = name:gsub("/+$", "")
      if name ~= "" then
        out[#out + 1] = { name = name, dir = dir }
      end
    end
  end
  return out
end

--- Is this something we can create or rename to?
---@param name string
---@return boolean ok, string? why
function M.valid(name)
  if name == "" then
    return false, "the name is empty"
  end
  if name:find "[%z\n\r]" then
    return false, "the name has a line break"
  end
  for segment in name:gmatch "[^/]+" do
    if segment == "." or segment == ".." then
      return false, "'.' and '..' are not names"
    end
  end
  return true
end

--- Absolute path of what was typed: relative to `base`, or absolute / `~` as typed
---@param base string
---@param name string
---@return string
function M.resolve(base, name)
  if name:sub(1, 1) == "/" or name:sub(1, 1) == "~" then
    return vim.fs.normalize(name)
  end
  return vim.fs.normalize(base .. "/" .. name)
end

---@param path string
---@param dir string
---@return boolean path is dir or lives inside it
function M.inside(path, dir)
  return path == dir or path:sub(1, #dir + 1) == dir .. "/"
end

--- Where something that lived at `old` is once `old` has moved to `new` (a buffer inside a renamed folder)
---@param path string
---@param old string
---@param new string
---@return string?
function M.rebase(path, old, new)
  if path == old then
    return new
  end
  if path:sub(1, #old + 1) == old .. "/" then
    return new .. path:sub(#old + 1)
  end
end

--- `note.go` → `note_copy.go`, then `note_copy2.go`… (the first one that does not exist)
---@param path string
---@param exists fun(path: string): boolean
---@return string
function M.copy_name(path, exists)
  local dir, file = vim.fs.dirname(path), vim.fs.basename(path)
  local stem, ext = file:match "^(.+)(%.[^.]+)$"
  stem, ext = stem or file, ext or ""
  local candidate = ("%s/%s_copy%s"):format(dir, stem, ext)
  local n = 2
  while exists(candidate) do
    candidate = ("%s/%s_copy%d%s"):format(dir, stem, n, ext)
    n = n + 1
  end
  return candidate
end

--- Shown path: relative to the project when inside it, else with `~`
---@param path string
---@param root string
---@return string
function M.display(path, root)
  if M.inside(path, root) and path ~= root then
    return path:sub(#root + 2)
  end
  return vim.fn.fnamemodify(path, ":~")
end

--- Name a trashed item is stored under: unique and still readable
---@param path string
---@param stamp string  e.g. "20261014-151230"
---@return string
function M.trash_name(path, stamp)
  return stamp .. "-" .. vim.fs.basename(path)
end

return M
