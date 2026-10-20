-- ── Recent files: what is remembered per project ─────────────────────────────
-- One JSON file (stdpath("state")/recent-files.json): project folder → { path, at }[] newest first. A file is
-- recorded under the project that holds it (the git root, else the folder you are in), so opening a file of another
-- project never lands in this one's list. Written in the background after a change and on exit.
local M = {}

M.FILE = vim.fn.stdpath "state" .. "/recent-files.json"
M.PER_PROJECT = 100
M.PROJECTS = 60

local data, dirty, timer

local function load()
  if data then
    return data
  end
  data = {}
  local f = io.open(M.FILE)
  if f then
    local ok, decoded = pcall(vim.json.decode, f:read "*a")
    f:close()
    if ok and type(decoded) == "table" and not vim.islist(decoded) then
      data = decoded
    end
  end
  return data
end

function M.save()
  if not (data and dirty) then
    return
  end
  dirty = false
  -- only the projects used last stay
  local keys = vim.tbl_keys(data)
  if #keys > M.PROJECTS then
    table.sort(keys, function(a, b)
      return ((data[a][1] or {}).at or 0) > ((data[b][1] or {}).at or 0)
    end)
    for i = M.PROJECTS + 1, #keys do
      data[keys[i]] = nil
    end
  end
  vim.fn.mkdir(vim.fs.dirname(M.FILE), "p")
  local f = io.open(M.FILE, "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

local function later()
  dirty = true
  if timer then
    return
  end
  timer = vim.uv.new_timer()
  timer:start(
    5000,
    0,
    vim.schedule_wrap(function()
      timer:close()
      timer = nil
      M.save()
    end)
  )
end

--- The project a file belongs to: the git root above it, else the folder you are working in when it is inside.
---@param path string
---@param cwd string
---@return string
function M.project_of(path, cwd)
  local list = require "recent.list"
  local root = vim.fs.root(path, ".git")
  if root and root ~= vim.uv.os_homedir() then
    return root
  end
  if list.inside(path, cwd) then
    return cwd
  end
  return vim.fs.dirname(path)
end

---@param project string
---@return RecentEntry[]
function M.get(project)
  return load()[project] or {}
end

---@return RecentEntry[]
function M.all()
  local out = {}
  for _, entries in pairs(load()) do
    vim.list_extend(out, entries)
  end
  return out
end

---@param project string
---@param path string
---@param at integer?
function M.record(project, path, at)
  local entries = load()[project] or {}
  entries = vim.tbl_filter(function(e)
    return e.path ~= path
  end, entries)
  table.insert(entries, 1, { path = path, at = at or os.time() })
  while #entries > M.PER_PROJECT do
    table.remove(entries)
  end
  data[project] = entries
  later()
end

---@param project string
---@param path string
function M.forget(project, path)
  local entries = load()[project]
  if entries then
    data[project] = vim.tbl_filter(function(e)
      return e.path ~= path
    end, entries)
    later()
  end
end

--- Tests: forget what was read.
function M.reset()
  data, dirty = nil, false
end

return M
