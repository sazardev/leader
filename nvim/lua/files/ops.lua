-- ── File operations: the file system side ────────────────────────────────────
-- Create, rename/move, copy, trash and restore. No UI and no buffers (files/buffers.lua follows what these change). Every
-- function returns `true` or `nil, reason`; none of them overwrites: if the destination exists it says so.
-- Deleting moves to a trash inside `stdpath("state")` so `<leader>Fu` can bring it back.
local paths = require "files.paths"

local uv = vim.uv

local M = {}

---@param path string
---@return boolean
function M.exists(path)
  return uv.fs_stat(path) ~= nil
end

---@param path string
---@return boolean
function M.is_dir(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

---@param path string
---@return boolean, string?
local function make_parent(path)
  local parent = vim.fs.dirname(path)
  if M.is_dir(parent) then
    return true
  end
  if M.exists(parent) then
    return false, parent .. " is a file"
  end
  local ok = vim.fn.mkdir(parent, "p") == 1
  return ok, not ok and ("could not create " .. parent) or nil
end

--- Creates an empty file or a folder (and the folders on the way)
---@param path string
---@param dir boolean
---@return boolean? ok, string? reason
function M.create(path, dir)
  if M.exists(path) then
    return nil, "already exists"
  end
  local made, why = make_parent(path)
  if not made then
    return nil, why
  end
  if dir then
    if vim.fn.mkdir(path, "p") ~= 1 then
      return nil, "could not create the folder"
    end
    return true
  end
  local f, err = io.open(path, "w")
  if not f then
    return nil, err
  end
  f:close()
  return true
end

---@param src string
---@param dst string
---@return boolean? ok, string? reason
function M.copy(src, dst)
  if M.exists(dst) then
    return nil, "already exists"
  end
  if paths.inside(dst, src) and M.is_dir(src) then
    return nil, "cannot copy a folder into itself"
  end
  local made, why = make_parent(dst)
  if not made then
    return nil, why
  end
  if not M.is_dir(src) then
    local ok, err = uv.fs_copyfile(src, dst)
    return ok or nil, err
  end
  vim.fn.mkdir(dst, "p")
  for name, kind in vim.fs.dir(src) do
    local ok, err = M.copy(src .. "/" .. name, dst .. "/" .. name)
    if not ok and kind ~= "link" then
      return nil, err
    end
  end
  return true
end

--- Renames or moves (the same thing on disk). Falls back to copy + delete across file systems
---@param old string
---@param new string
---@return boolean? ok, string? reason
function M.rename(old, new)
  if old == new then
    return nil, "that is the same path"
  end
  if M.exists(new) then
    return nil, "already exists"
  end
  if M.is_dir(old) and paths.inside(new, old) then
    return nil, "cannot move a folder into itself"
  end
  local made, why = make_parent(new)
  if not made then
    return nil, why
  end
  local ok, err = uv.fs_rename(old, new)
  if ok then
    return true
  end
  if tostring(err):find("EXDEV", 1, true) then
    local copied, copy_err = M.copy(old, new)
    if not copied then
      return nil, copy_err
    end
    vim.fn.delete(old, "rf")
    return true
  end
  return nil, err
end

--- How much a folder holds (to warn before deleting it)
---@param path string
---@return integer files, integer dirs
function M.count(path)
  local files, dirs = 0, 0
  for _, kind in vim.fs.dir(path, { depth = math.huge }) do
    if kind == "directory" then
      dirs = dirs + 1
    else
      files = files + 1
    end
  end
  return files, dirs
end

-- ── trash ───────────────────────────────────────────────────────────────────
local KEEP_DAYS = 30

---@return string
function M.trash_dir()
  return vim.fn.stdpath "state" .. "/trash"
end

---@return { from: string, stored: string, at: integer }[]
local function read_index()
  local f = io.open(M.trash_dir() .. "/index.json", "r")
  if not f then
    return {}
  end
  local ok, data = pcall(vim.json.decode, f:read "*a")
  f:close()
  return ok and type(data) == "table" and data or {}
end

---@param index table[]
local function write_index(index)
  vim.fn.mkdir(M.trash_dir(), "p")
  local f = io.open(M.trash_dir() .. "/index.json", "w")
  if f then
    f:write(vim.json.encode(index))
    f:close()
  end
end

--- Moves to the trash (nothing is lost until it is older than 30 days)
---@param path string
---@return { from: string, stored: string, at: integer }? entry, string? reason
function M.trash(path)
  local now = os.time()
  local stored = M.trash_dir() .. "/" .. paths.trash_name(path, os.date("%Y%m%d-%H%M%S", now))
  local base, n = stored, 2
  while M.exists(stored) do -- two things with the same name trashed within a second
    stored, n = base .. "-" .. n, n + 1
  end
  local ok, why = M.rename(path, stored)
  if not ok then
    return nil, why
  end
  local entry = { from = path, stored = stored, at = now }
  local index = vim.tbl_filter(function(e)
    if now - e.at > KEEP_DAYS * 86400 then
      vim.fn.delete(e.stored, "rf") -- the oldest leave for good
      return false
    end
    return M.exists(e.stored)
  end, read_index())
  index[#index + 1] = entry
  write_index(index)
  return entry
end

---@return { from: string, stored: string, at: integer }?
function M.last_trashed()
  local index = read_index()
  for i = #index, 1, -1 do
    if M.exists(index[i].stored) then
      return index[i]
    end
  end
end

--- Brings the most recently trashed item back to where it was
---@return string? restored_path, string? reason
function M.restore()
  local entry = M.last_trashed()
  if not entry then
    return nil, "the trash is empty"
  end
  local ok, why = M.rename(entry.stored, entry.from)
  if not ok then
    return nil, ("%s: %s"):format(vim.fn.fnamemodify(entry.from, ":~:."), why)
  end
  write_index(vim.tbl_filter(function(e)
    return e.stored ~= entry.stored
  end, read_index()))
  return entry.from
end

-- ── folders to pick from ────────────────────────────────────────────────────
local SKIP = {
  [".git"] = true,
  node_modules = true,
  vendor = true,
  target = true,
  dist = true,
  build = true,
  [".venv"] = true,
  __pycache__ = true,
  [".next"] = true,
}

--- The project's folders, relative to `root`, shortest first (capped: a huge tree would make a useless list)
---@param root string
---@param skip string? a folder (and what is inside it) to leave out: the one being moved
---@return string[]
function M.folders(root, skip)
  local out = {}
  for name, kind in
    vim.fs.dir(root, {
      depth = 5,
      skip = function(dir)
        return not SKIP[vim.fs.basename(dir)]
      end,
    })
  do
    local full = root .. "/" .. name
    local hidden = false
    for segment in name:gmatch "[^/]+" do
      hidden = hidden or SKIP[segment] or false
    end
    if kind == "directory" and not hidden and not (skip and paths.inside(full, skip)) then
      out[#out + 1] = name
    end
  end
  table.sort(out, function(a, b)
    local da, db = select(2, a:gsub("/", "")), select(2, b:gsub("/", ""))
    return da == db and a < b or da < db
  end)
  return vim.list_slice(out, 1, 400)
end

return M
