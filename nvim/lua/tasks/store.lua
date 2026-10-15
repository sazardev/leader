-- ── What the last run was ────────────────────────────────────────────────────
-- `stdpath("state")/tasks.json`: the last task started in each project (so "run last" survives a restart and a project
-- switch) and the last one anywhere. A task is stored whole (command, cwd, arguments): running it again lists nothing.
local M = {}

---@return string
function M.path()
  return vim.fn.stdpath "state" .. "/tasks.json"
end

---@return { last: table<string, table>, recent: table? }
function M.read()
  local f = io.open(M.path(), "r")
  if not f then
    return { last = {} }
  end
  local ok, data = pcall(vim.json.decode, f:read "*a")
  f:close()
  if not ok or type(data) ~= "table" then
    return { last = {} }
  end
  data.last = type(data.last) == "table" and data.last or {}
  return data
end

---@param data table
local function write(data)
  vim.fn.mkdir(vim.fs.dirname(M.path()), "p")
  local f = io.open(M.path(), "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

---@param project string
---@param entry table { name, cmd, cwd, extra? }
function M.set_last(project, entry)
  local data = M.read()
  data.last[project] = entry
  data.recent = entry
  write(data)
end

--- The last task of `project`, else the last one anywhere
---@param project string
---@return table?
function M.get_last(project)
  local data = M.read()
  return data.last[project] or data.recent
end

return M
