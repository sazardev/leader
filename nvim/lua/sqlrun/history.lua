-- ── Query history (<leader>Qh) ───────────────────────────────────────────────
-- What ran in a project, newest first, in the state dir (one file, no passwords: only the connection's name). `add` is
-- pure (same text replaces the old entry, the list is capped by `settings.sql.history`), so test-langs.lua can check it.
-- Enter puts the statement back in the buffer; `<C-r>` runs it again.
local log = require "utils.log"

local M = {}

M.MAX = 100

---@class SqlHistoryEntry
---@field text string
---@field label string
---@field connection string
---@field kind string
---@field ok boolean
---@field ms integer
---@field at integer

---@return string
local function path()
  return vim.fn.stdpath "state" .. "/sql-history.json"
end

---@return table<string, SqlHistoryEntry[]>
local function load_all()
  local f = io.open(path(), "r")
  if not f then
    return {}
  end
  local text = f:read "*a"
  f:close()
  local ok, data = pcall(vim.json.decode, text)
  return ok and type(data) == "table" and data or {}
end

---@param data table
local function save_all(data)
  vim.fn.mkdir(vim.fs.dirname(path()), "p")
  local f = io.open(path(), "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

--- The history of a project, newest first
---@param root string
---@return SqlHistoryEntry[]
function M.load(root)
  local data = load_all()
  return type(data[root]) == "table" and data[root] or {}
end

--- The list with `entry` on top (pure): the same text replaces the old one and the list is capped
---@param list SqlHistoryEntry[]
---@param entry SqlHistoryEntry
---@param max integer?
---@return SqlHistoryEntry[]
function M.add(list, entry, max)
  local out = { entry }
  for _, item in ipairs(list or {}) do
    if item.text ~= entry.text then
      out[#out + 1] = item
    end
  end
  max = max or M.MAX
  while #out > max do
    table.remove(out)
  end
  return out
end

--- Remembers one run
---@param root string
---@param entry SqlHistoryEntry
function M.record(root, entry)
  local max = require("core.settings").sql.history or M.MAX
  if max <= 0 then
    return
  end
  local data = load_all()
  data[root] = M.add(type(data[root]) == "table" and data[root] or {}, entry, max)
  save_all(data)
end

--- The first line of a statement, trimmed, for the picker
---@param text string
---@param width integer?
---@return string
function M.title(text, width)
  local first = (text:gsub("%s+", " "):match "^%s*(.-)%s*$")
  width = width or 90
  if vim.fn.strdisplaywidth(first) > width then
    first = vim.fn.strcharpart(first, 0, width - 1) .. "…"
  end
  return first
end

---@param entry SqlHistoryEntry
---@return string
local function when(entry)
  local at = tonumber(entry.at) or 0
  return at > 0 and os.date("%m-%d %H:%M", at) or ""
end

--- The history of this project as a picker: Enter inserts, `<C-r>` runs
---@param root string
function M.pick(root)
  local entries = M.load(root)
  if #entries == 0 then
    return log.info "SQL: nothing ran in this project yet"
  end
  require("tasks.picker").choose(
    vim.tbl_map(function(entry)
      local ok = entry.ok == false and "failed" or "ok"
      return {
        label = M.title(entry.text),
        desc = ("%s · %s · %s"):format(when(entry), entry.connection or entry.kind or "?", ok),
        value = entry,
        search = entry.text,
      }
    end, entries),
    {
      title = "SQL history · " .. vim.fn.fnamemodify(root, ":~"),
      hint = "Enter insert · C-r run again",
      width = 64,
      maps = {
        {
          "<C-r>",
          function(entry)
            require("sqlrun").run_text(entry.text)
          end,
        },
      },
    },
    function(entry)
      vim.api.nvim_put(vim.split(entry.text, "\n", { plain = true }), "l", true, true)
    end
  )
end

return M
